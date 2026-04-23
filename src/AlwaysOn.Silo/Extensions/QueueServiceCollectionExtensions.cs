using AlwaysOn.Shared.Constants;
using AlwaysOn.Silo.Caching;
using AlwaysOn.Silo.Grains;
using AlwaysOn.Silo.Hubs;
using AlwaysOn.Silo.Queueing;
using Azure.Identity;
using Azure.Messaging.EventGrid.Namespaces;
using StackExchange.Redis;

namespace AlwaysOn.Silo.Extensions;

/// <summary>
/// Wires up the event-driven queue stack (Redis cache + queue index, Event Grid
/// notifier + consumer, SignalR hub) on the silo. Keeps <c>Program.cs</c>
/// focused on Orleans bootstrap.
/// </summary>
internal static class QueueServiceCollectionExtensions
{
    public static IHostApplicationBuilder AddEventReadCache(this IHostApplicationBuilder builder)
    {
        var redisConnectionString = builder.Configuration.GetConnectionString(AspireConstants.RedisCache);
        var hasRedis = !string.IsNullOrWhiteSpace(redisConnectionString);

        if (hasRedis)
        {
            builder.Services.AddSingleton<IConnectionMultiplexer>(sp =>
            {
                var logger = sp.GetRequiredService<ILogger<RedisEventReadCache>>();

                var configOptions = ConfigurationOptions.Parse(redisConnectionString!);
                configOptions.Ssl = true;
                configOptions.AbortOnConnectFail = false;
                // Stay on RESP2. Azure Cache for Redis Basic/Standard runs
                // Redis 6.x, which does not fully support RESP3 — negotiating
                // HELLO 3 introduces failed handshakes and extra round-trips
                // per command. RESP3 would only help on the Enterprise tier.
                // Fail fast if Redis is unreachable rather than letting the
                // default 5s syncTimeout stack up on every cache read+write.
                configOptions.ConnectTimeout = 2000;
                configOptions.SyncTimeout = 2000;

                // AKS Workload Identity uses federated OIDC token exchange,
                // NOT the IMDS endpoint. ConfigureForAzureWithUserAssignedManagedIdentityAsync
                // uses ManagedIdentityCredential (IMDS) and fails with
                // "Identity not found" on workload-identity pods.
                //
                // WorkloadIdentityCredential reads AZURE_CLIENT_ID / TENANT_ID /
                // FEDERATED_TOKEN_FILE / AUTHORITY_HOST injected by the
                // workload-identity webhook and performs the federated
                // exchange directly — no IMDS involved.
                var credential = new WorkloadIdentityCredential();
                var uamiClientId = Environment.GetEnvironmentVariable("AZURE_CLIENT_ID");
                logger.LogInformation("Configuring Redis AAD auth with workload identity (client ID: {ClientId}).",
                    uamiClientId ?? "<unset>");

                configOptions.ConfigureForAzureWithTokenCredentialAsync(credential)
                    .GetAwaiter().GetResult();

                var multiplexer = ConnectionMultiplexer.Connect(configOptions);

                // Surface connection-level errors instead of letting them rot
                // in the multiplexer's internal log. Without this, an auth
                // failure or DNS miss just manifests as 5-second command
                // timeouts with no explanation.
                multiplexer.ConnectionFailed += (_, e) =>
                    logger.LogError(e.Exception, "Redis connection failed. Type={FailureType} Endpoint={Endpoint}", e.FailureType, e.EndPoint);
                multiplexer.ConnectionRestored += (_, e) =>
                    logger.LogInformation("Redis connection restored. Endpoint={Endpoint}", e.EndPoint);
                multiplexer.InternalError += (_, e) =>
                    logger.LogError(e.Exception, "Redis internal error. Origin={Origin}", e.Origin);

                return multiplexer;
            });

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

        return builder;
    }

    public static IHostApplicationBuilder AddReservationMessaging(this IHostApplicationBuilder builder)
    {
        var eventGridEndpoint = builder.Configuration.GetConnectionString(AspireConstants.EventGrid);

        if (!string.IsNullOrWhiteSpace(eventGridEndpoint))
        {
            var endpoint = new Uri(eventGridEndpoint);
            // WorkloadIdentityCredential goes straight to the federated OIDC
            // exchange using the env vars injected by the AKS workload-identity
            // webhook. DefaultAzureCredential would also work (it has
            // WorkloadIdentityCredential in its chain) but probes other sources
            // first, adding startup latency and noisier error logs.
            var credential = new WorkloadIdentityCredential();

            builder.Services.AddSingleton(
                new EventGridSenderClient(endpoint, AspireConstants.EventGridTopic, credential));
            builder.Services.AddSingleton(
                new EventGridReceiverClient(endpoint, AspireConstants.EventGridTopic, AspireConstants.ReservationsSubscription, credential));

            builder.Services.AddSingleton<IReservationNotifier, EventGridReservationNotifier>();
            builder.Services.AddHostedService<ReservationReadyConsumer>();
        }
        else
        {
            builder.Services.AddSingleton<NullReservationNotifier>();
            builder.Services.AddSingleton<IReservationNotifier>(sp => sp.GetRequiredService<NullReservationNotifier>());
        }

        return builder;
    }

    public static IHostApplicationBuilder AddReservationQueueCore(this IHostApplicationBuilder builder)
    {
        builder.Services.AddOptions<ReservationQueueOptions>()
            .Bind(builder.Configuration.GetSection("ReservationQueue"));
        builder.Services.AddSingleton(TimeProvider.System);

        builder.Services.AddSignalR();

        return builder;
    }

    public static WebApplication MapQueueHub(this WebApplication app)
    {
        app.MapHub<QueueHub>("/hubs/queue");

        return app;
    }
}
