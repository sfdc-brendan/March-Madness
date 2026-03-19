public with sharing class MarchMadnessScheduler implements Schedulable {

    private static final String JOB_PREFIX = 'March_Madness_';
    private static final String DAILY_CRON = '0 0 6 * * ?';
    private static final String TWICE_DAILY_CRON = '0 0 8,18 * * ?';
    private static final String HOURLY_CRON = '0 0 * * * ?';
    private static final String GAMEDAY_CRON = '0 0 9,12,15,18,21 * * ?';

    public void execute(SchedulableContext ctx) {
        System.enqueueJob(new MarchMadnessQueueable('full'));
    }

    public static void sweepContenderNews() {
        ContenderNewsSweep.startSweep();
    }

    public static void scheduleNewsSweep() {
        System.schedule(
            JOB_PREFIX + 'NewsSweep_Morning',
            '0 0 7 * * ?',
            new NewsSweepScheduler()
        );
        System.schedule(
            JOB_PREFIX + 'NewsSweep_Afternoon',
            '0 0 14 * * ?',
            new NewsSweepScheduler()
        );
        System.schedule(
            JOB_PREFIX + 'NewsSweep_Evening',
            '0 0 20 * * ?',
            new NewsSweepScheduler()
        );
    }

    public class NewsSweepScheduler implements Schedulable {
        public void execute(SchedulableContext ctx) {
            ContenderNewsSweep.startSweep();
        }
    }

    public static void scheduleDaily() {
        System.schedule(JOB_PREFIX + 'Daily', DAILY_CRON, new MarchMadnessScheduler());
    }

    public static void scheduleTwiceDaily() {
        System.schedule(JOB_PREFIX + 'TwiceDaily', TWICE_DAILY_CRON, new MarchMadnessScheduler());
    }

    public static void scheduleHourly() {
        System.schedule(JOB_PREFIX + 'Hourly', HOURLY_CRON, new MarchMadnessScheduler());
    }

    public static void scheduleGameDay() {
        System.schedule(JOB_PREFIX + 'GameDay', GAMEDAY_CRON, new MarchMadnessScheduler());
    }

    public static void unschedule() {
        List<CronTrigger> jobs = [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :(JOB_PREFIX + '%')
        ];
        for (CronTrigger job : jobs) {
            System.abortJob(job.Id);
        }
    }

    public static String getScheduleStatus() {
        List<CronTrigger> jobs = [
            SELECT CronJobDetail.Name, State, NextFireTime
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :(JOB_PREFIX + '%')
        ];
        if (jobs.isEmpty()) return 'No scheduled jobs found.';
        String status = '';
        for (CronTrigger job : jobs) {
            status += job.CronJobDetail.Name + ' | ' + job.State + ' | Next: ' + job.NextFireTime + '\n';
        }
        return status;
    }

    public class MarchMadnessQueueable implements Queueable, Database.AllowsCallouts {

        private String mode;
        private Id teamIdForResearch;
        private List<Id> pendingTeamIds;

        public MarchMadnessQueueable(String mode) {
            this.mode = mode;
        }

        public MarchMadnessQueueable(String mode, Id teamId, List<Id> remaining) {
            this.mode = mode;
            this.teamIdForResearch = teamId;
            this.pendingTeamIds = remaining;
        }

        public void execute(QueueableContext ctx) {
            try {
                if (mode == 'teamResearch') {
                    executeTeamResearch();
                    return;
                }
                if (mode == 'teamNews') {
                    executeTeamNews();
                    return;
                }

                Tournament__c tournament = getActiveTournament();
                if (tournament == null) {
                    System.debug('No active/upcoming tournament. Skipping.');
                    return;
                }
                Id tournamentId = tournament.Id;
                String status = tournament.Status__c;

                BracketDataService.loadTeamStats(tournamentId);
                System.debug('Team stats refreshed from ESPN.');

                if (status == 'Active') {
                    BracketDataService.updateGameResults(tournamentId);
                    System.debug('Game results updated.');
                    updatePredictionsForScheduledGames(tournamentId);
                    refreshBettingLines(tournamentId);
                }

                chainTeamResearch(tournamentId);

            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'MarchMadnessQueueable failed: ' + e.getMessage() + '\n' + e.getStackTraceString());
            }
        }

        private Tournament__c getActiveTournament() {
            List<Tournament__c> tournaments = [
                SELECT Id, Status__c
                FROM Tournament__c
                WHERE Status__c IN ('Active', 'Upcoming')
                ORDER BY Status__c ASC, Year__c DESC
                LIMIT 1
            ];
            return tournaments.isEmpty() ? null : tournaments[0];
        }

        private void updatePredictionsForScheduledGames(Id tournamentId) {
            List<Game__c> scheduledGames = [
                SELECT Id FROM Game__c
                WHERE Status__c = 'Scheduled'
                    AND Team_1__c != null AND Team_2__c != null
                    AND Tournament__c = :tournamentId
                ORDER BY Game_Date__c ASC
                LIMIT 50
            ];

            for (Game__c game : scheduledGames) {
                try {
                    PredictionEngine.predictAndSave(game.Id);
                } catch (Exception e) {
                    System.debug(LoggingLevel.WARN,
                        'Prediction failed for game ' + game.Id + ': ' + e.getMessage());
                }
            }
            System.debug('Predictions updated for ' + scheduledGames.size() + ' scheduled games.');
        }

        private void refreshBettingLines(Id tournamentId) {
            try {
                Integer updated = BettingLineService.refreshLinesForTournament(tournamentId);
                System.debug('Betting lines updated for ' + updated + ' games.');
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Betting line refresh failed: ' + e.getMessage());
            }
        }

        private void chainTeamResearch(Id tournamentId) {
            List<Team__c> teamsNeedingResearch = [
                SELECT Id FROM Team__c
                WHERE Tournament__c = :tournamentId
                    AND Record_Wins__c > 0
                    AND Id NOT IN (
                        SELECT Team__c FROM Team_Research__c
                        WHERE Is_Current__c = true
                            AND Research_Date__c >= :DateTime.now().addHours(-12)
                    )
                ORDER BY NET_Ranking__c ASC NULLS LAST
                LIMIT 10
            ];

            if (teamsNeedingResearch.isEmpty()) {
                System.debug('All teams have recent research. Skipping.');
                return;
            }

            List<Id> ids = new List<Id>();
            for (Team__c t : teamsNeedingResearch) {
                ids.add(t.Id);
            }

            Id firstId = ids.remove(0);
            System.enqueueJob(new MarchMadnessQueueable('teamResearch', firstId, ids));
            System.debug('Chained research for ' + (ids.size() + 1) + ' teams.');
        }

        private void executeTeamResearch() {
            if (teamIdForResearch == null) return;

            try {
                NewsIngestionService.ingestNewsForTeam(teamIdForResearch);
                System.debug('Research completed for team: ' + teamIdForResearch);
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN,
                    'Research failed for team ' + teamIdForResearch + ': ' + e.getMessage());
            }

            if (pendingTeamIds != null && !pendingTeamIds.isEmpty()) {
                Id nextId = pendingTeamIds.remove(0);
                System.enqueueJob(new MarchMadnessQueueable('teamNews', nextId, pendingTeamIds));
            }
        }

        private void executeTeamNews() {
            if (teamIdForResearch == null) return;

            try {
                Team__c t = [SELECT Id, Name FROM Team__c WHERE Id = :teamIdForResearch LIMIT 1];
                String prompt = TeamResearchPromptBuilder.buildGroundedNewsPrompt(t.Name);
                GeminiAPIService.GeminiResponse resp = GeminiAPIService.generateGroundedContent(prompt);
                if (resp.success && String.isNotBlank(resp.text)) {
                    List<News_Article__c> articles = GeminiResponseParser.parseGroundedNewsArticles(
                        resp.text, t.Id, resp.groundingSources
                    );
                    if (!articles.isEmpty()) {
                        insert articles;
                        System.debug('Inserted ' + articles.size() + ' grounded articles for ' + t.Name);
                    }
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN,
                    'News failed for team ' + teamIdForResearch + ': ' + e.getMessage());
            }

            if (pendingTeamIds != null && !pendingTeamIds.isEmpty()) {
                Id nextId = pendingTeamIds.remove(0);
                System.enqueueJob(new MarchMadnessQueueable('teamResearch', nextId, pendingTeamIds));
            }
        }
    }
}
