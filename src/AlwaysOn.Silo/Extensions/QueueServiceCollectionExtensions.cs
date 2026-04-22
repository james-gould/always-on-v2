using AlwaysOn.Shared.Constants;
using AlwaysOn.Silo.Caching;
using AlwaysOn.Silo.Grains;
using AlwaysOn.Silo.Hubs;
using AlwaysOn.Silo.Queueing;
using Azure.Identity;
using Azure.Messaging.EventGrid.Namespaces;

namespace AlwaysOn.Silo.Extensions;

/// <summary>
/// Wires up the event-driven queue stack (Redis cache + queue index, Event Grid
/// notifier + consumer, SignalR hub) on the silo. Keeps <c>Program.cs</c>
/// focused on Orleans bootstrap.
/// </summary>
internal static class QueueServiceCollectionExtensions
{
    /// <summary>
    /// Registers the Redis-backed event read cache and queue index when a Redis
    /// connection string is configured. Falls back to in-process implementations
    /// (used by the in-memory integration-test mode) so endpoint contracts
    /// remain unchanged.
    /// </summary>
    public static IHostApplicationBuilder AddEventReadCache(this IHostApplicationBuilder builder)
    {
        var hasRedis = !string.IsNullOrWhiteSpace(
            builder.Configuration.GetConnectionString(AspireConstants.RedisCache));

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

        return builder;
    }

    /// <summary>
    /// Registers the Event Grid notifier + background consumer when an Event
    /// Grid connection string is configured, or a no-op notifier otherwise.
    /// </summary>
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

    /// <summary>
    /// Registers queue-grain options, the shared <see cref="TimeProvider"/> and
    /// the self-hosted SignalR hub used to push reservation-ready events.
    /// </summary>
    public static IHostApplicationBuilder AddReservationQueueCore(this IHostApplicationBuilder builder)
    {
        builder.Services.AddOptions<ReservationQueueOptions>()
            .Bind(builder.Configuration.GetSection("ReservationQueue"));
        builder.Services.AddSingleton(TimeProvider.System);

        // Self-hosted SignalR (ASP.NET Core, no separate Azure SignalR Service
        // or emulator) keeps the dev-ex simple and puts the hub next to its
        // only consumer, ReservationReadyConsumer.
        builder.Services.AddSignalR();

        return builder;
    }

    /// <summary>Maps the queue-ready SignalR hub route.</summary>
    public static WebApplication MapQueueHub(this WebApplication app)
    {
        app.MapHub<QueueHub>("/hubs/queue");
        return app;
    }
}
