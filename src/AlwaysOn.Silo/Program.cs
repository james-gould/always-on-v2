using AlwaysOn.Shared.Constants;
using AlwaysOn.Silo.Endpoints;

var builder = WebApplication.CreateBuilder(args);

builder.AddServiceDefaults();

var useInMemoryOrleansForTests = bool.TryParse(builder.Configuration["Testing:UseInMemoryOrleans"], out var parsedTestMode)
    && parsedTestMode;

if (useInMemoryOrleansForTests)
{
    builder.UseOrleans(siloBuilder =>
    {
        siloBuilder.UseLocalhostClustering();
        siloBuilder.UseInMemoryReminderService();
        siloBuilder.AddMemoryGrainStorageAsDefault();
    });
}
else
{
    var cosmosConnectionString = builder.Configuration.GetConnectionString(AspireConstants.CosmosDatabase)
        ?? builder.Configuration.GetConnectionString(AspireConstants.LegacyCosmosConnectionString);
    if (string.IsNullOrWhiteSpace(cosmosConnectionString))
    {
        throw new InvalidOperationException($"Missing ConnectionStrings:{AspireConstants.CosmosDatabase} configuration.");
    }

    var cosmosDatabaseName = builder.Configuration["Orleans:Cosmos:DatabaseName"] ?? AspireConstants.CosmosDatabase;
    var clusteringContainerName = builder.Configuration["Orleans:Cosmos:ClusteringContainerName"] ?? AspireConstants.OrleansClusteringContainer;
    var grainStateContainerName = builder.Configuration["Orleans:Cosmos:GrainStateContainerName"] ?? AspireConstants.OrleansGrainStateContainer;
    var remindersContainerName = builder.Configuration["Orleans:Cosmos:RemindersContainerName"] ?? AspireConstants.OrleansRemindersContainer;
    var isResourceCreationEnabled = builder.Configuration.GetValue("Orleans:Cosmos:IsResourceCreationEnabled", true);

    builder.UseOrleans(siloBuilder =>
    {
        siloBuilder.UseCosmosClustering(options =>
        {
            options.ConfigureCosmosClient(cosmosConnectionString);
            options.DatabaseName = cosmosDatabaseName;
            options.ContainerName = clusteringContainerName;
            options.IsResourceCreationEnabled = isResourceCreationEnabled;
        });

        siloBuilder.UseCosmosReminderService(options =>
        {
            options.ConfigureCosmosClient(cosmosConnectionString);
            options.DatabaseName = cosmosDatabaseName;
            options.ContainerName = remindersContainerName;
            options.IsResourceCreationEnabled = isResourceCreationEnabled;
        });

        siloBuilder.AddCosmosGrainStorageAsDefault(options =>
        {
            options.ConfigureCosmosClient(cosmosConnectionString);
            options.DatabaseName = cosmosDatabaseName;
            options.ContainerName = grainStateContainerName;
            options.IsResourceCreationEnabled = isResourceCreationEnabled;
        });
    });
}

var app = builder.Build();

app.MapDefaultEndpoints();
app.MapEventEndpoints();
app.MapOrderEndpoints();
app.MapTicketEndpoints();

app.Run();
