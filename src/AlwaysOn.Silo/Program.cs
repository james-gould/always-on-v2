using AlwaysOn.Shared.Constants;
using AlwaysOn.Silo.Endpoints;
using AlwaysOn.Silo.Extensions;
using Azure.Identity;

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
    var cosmosAccountEndpoint = builder.Configuration["Orleans:Cosmos:AccountEndpoint"];

    if (string.IsNullOrWhiteSpace(cosmosConnectionString) && string.IsNullOrWhiteSpace(cosmosAccountEndpoint))
    {
        throw new InvalidOperationException(
            $"Missing ConnectionStrings:{AspireConstants.CosmosDatabase} or Orleans:Cosmos:AccountEndpoint configuration.");
    }

    var useAadAuth = !string.IsNullOrWhiteSpace(cosmosAccountEndpoint);
    var credential = useAadAuth ? new WorkloadIdentityCredential() : null;

    var cosmosDatabaseName = builder.Configuration["Orleans:Cosmos:DatabaseName"] ?? AspireConstants.CosmosDatabase;
    var clusteringContainerName = builder.Configuration["Orleans:Cosmos:ClusteringContainerName"] ?? AspireConstants.OrleansClusteringContainer;
    var grainStateContainerName = builder.Configuration["Orleans:Cosmos:GrainStateContainerName"] ?? AspireConstants.OrleansGrainStateContainer;
    var remindersContainerName = builder.Configuration["Orleans:Cosmos:RemindersContainerName"] ?? AspireConstants.OrleansRemindersContainer;
    var isResourceCreationEnabled = builder.Configuration.GetValue("Orleans:Cosmos:IsResourceCreationEnabled", true);

    builder.UseOrleans(siloBuilder =>
    {
        siloBuilder.UseCosmosClustering(options =>
        {
            if (useAadAuth)
                options.ConfigureCosmosClient(cosmosAccountEndpoint!, credential!);
            else
                options.ConfigureCosmosClient(cosmosConnectionString!);
            options.DatabaseName = cosmosDatabaseName;
            options.ContainerName = clusteringContainerName;
            options.IsResourceCreationEnabled = isResourceCreationEnabled;
        });

        siloBuilder.UseCosmosReminderService(options =>
        {
            if (useAadAuth)
                options.ConfigureCosmosClient(cosmosAccountEndpoint!, credential!);
            else
                options.ConfigureCosmosClient(cosmosConnectionString!);
            options.DatabaseName = cosmosDatabaseName;
            options.ContainerName = remindersContainerName;
            options.IsResourceCreationEnabled = isResourceCreationEnabled;
        });

        siloBuilder.AddCosmosGrainStorageAsDefault(options =>
        {
            if (useAadAuth)
                options.ConfigureCosmosClient(cosmosAccountEndpoint!, credential!);
            else
                options.ConfigureCosmosClient(cosmosConnectionString!);
            options.DatabaseName = cosmosDatabaseName;
            options.ContainerName = grainStateContainerName;
            options.IsResourceCreationEnabled = isResourceCreationEnabled;
        });
    });
}

builder.AddEventReadCache();
builder.AddReservationMessaging();
builder.AddReservationQueueCore();

var app = builder.Build();

app.MapDefaultEndpoints();
app.MapEventEndpoints();
app.MapOrderEndpoints();
app.MapTicketEndpoints();
app.MapQueueEndpoints();
app.MapQueueHub();

app.Run();
