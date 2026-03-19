public with sharing class PredictionModelQueueable implements Queueable, Database.AllowsCallouts {

    private Id gameId;
    private String modelType;
    private String nextModelType;

    public PredictionModelQueueable(Id gameId, String modelType) {
        this(gameId, modelType, null);
    }

    public PredictionModelQueueable(Id gameId, String modelType, String nextModelType) {
        this.gameId = gameId;
        this.modelType = modelType;
        this.nextModelType = nextModelType;
    }

    public void execute(QueueableContext context) {
        try {
            if (modelType == 'Mascot Battle') {
                MascotPredictionEngine.predictAndSave(gameId);
            } else if (modelType == 'AI Research') {
                AIPredictionEngine.predictAndSave(gameId);
            } else {
                PredictionEngine.predictAndSave(gameId);
            }
            System.debug(modelType + ' prediction saved for game ' + gameId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, modelType + ' prediction failed for game ' + gameId + ': ' + e.getMessage());
        }

        if (String.isNotBlank(nextModelType)) {
            System.enqueueJob(new PredictionModelQueueable(gameId, nextModelType));
        }
    }
}
