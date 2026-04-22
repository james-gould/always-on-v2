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
            var configOptions = ConfigurationOptions.Parse(redisConnectionString!);
            configOptions.AbortOnConnectFail = false;
            configOptions.Ssl = true;

            // Acquire the AAD token and connect eagerly at startup rather than
            // inside a lazy DI factory. Doing this inside the factory meant any
            // token-acquisition failure (or transient credential hiccup)
            // re-threw during singleton resolution of IEventReadCache and
            // IQueueIndex on the first request, surfacing as an HTTP 500 on
            // every endpoint. Failing fast here surfaces misconfiguration to
            // the platform (pod restart) and keeps the request path
            // exception-free on Redis setup.
            configOptions.ConfigureForAzureWithTokenCredentialAsync(new DefaultAzureCredential())
                .ConfigureAwait(false).GetAwaiter().GetResult();
            var multiplexer = ConnectionMultiplexer.Connect(configOptions);

            builder.Services.AddSingleton<IConnectionMultiplexer>(multiplexer);

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
            var credential = new DefaultAzureCredential();

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
