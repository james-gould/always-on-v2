using AlwaysOn.Shared.Constants;
using AlwaysOn.Silo.Caching;
using AlwaysOn.Silo.Endpoints;
using AlwaysOn.Silo.Grains;
using AlwaysOn.Silo.Hubs;
using AlwaysOn.Silo.Queueing;
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

    // Use AAD auth when AccountEndpoint is provided, otherwise fall back to connection string
    var useAadAuth = !string.IsNullOrWhiteSpace(cosmosAccountEndpoint);
    var credential = useAadAuth ? new DefaultAzureCredential() : null;

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

// Redis-backed read cache for GET /events/{id}. If no Redis connection string
// is configured (e.g. integration-test mode) fall back to an in-process cache
// so the endpoint contract is unchanged.
var hasRedis = !string.IsNullOrWhiteSpace(builder.Configuration.GetConnectionString(AspireConstants.RedisCache));
if (hasRedis)
{
    builder.AddRedisClient(AspireConstants.RedisCache);
    builder.Services.AddOptions<EventReadCacheOptions>()
        .Bind(builder.Configuration.GetSection("EventReadCache"));
    builder.Services.AddSingleton<IEventReadCache, RedisEventReadCache>();
    builder.Services.AddSingleton<IQueueIndex, RedisQueueIndex>();
}
else
{
    builder.Services.AddSingleton<IEventReadCache, InMemoryEventReadCache>();
    builder.Services.AddSingleton<IQueueIndex, InMemoryQueueIndex>();
}

// Service Bus reservation notifier. Falls back to an in-memory no-op when not
// configured so integration tests run without a broker.
var hasServiceBus = !string.IsNullOrWhiteSpace(builder.Configuration.GetConnectionString(AspireConstants.ServiceBus))
    || !string.IsNullOrWhiteSpace(builder.Configuration[$"ConnectionStrings:{AspireConstants.ServiceBus}"]);
if (hasServiceBus)
{
    builder.AddAzureServiceBusClient(AspireConstants.ServiceBus);
    builder.Services.AddSingleton<IReservationNotifier, ServiceBusReservationNotifier>();
    builder.Services.AddHostedService<ReservationReadyConsumer>();
}
else
{
    builder.Services.AddSingleton<NullReservationNotifier>();
    builder.Services.AddSingleton<IReservationNotifier>(sp => sp.GetRequiredService<NullReservationNotifier>());
}

builder.Services.AddOptions<ReservationQueueOptions>()
    .Bind(builder.Configuration.GetSection("ReservationQueue"));
builder.Services.AddSingleton(TimeProvider.System);

// Self-hosted SignalR for pushing reservation-ready notifications to clients.
// Hosting in-cluster (AKS) keeps the dev-ex simple — no separate Azure SignalR
// Service or emulator to wire into the AppHost.
builder.Services.AddSignalR();

var app = builder.Build();

app.MapDefaultEndpoints();
app.MapEventEndpoints();
app.MapOrderEndpoints();
app.MapTicketEndpoints();
app.MapQueueEndpoints();
app.MapHub<QueueHub>("/hubs/queue");

app.Run();
