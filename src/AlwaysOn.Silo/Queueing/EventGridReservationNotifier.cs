using Azure.Messaging;
using Azure.Messaging.EventGrid.Namespaces;

namespace AlwaysOn.Silo.Queueing;

internal sealed class EventGridReservationNotifier(
    EventGridSenderClient senderClient,
    ILogger<EventGridReservationNotifier> logger) : IReservationNotifier
{
    public async Task PublishReadyAsync(ReservationReadyMessage message, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(message);

        var cloudEvent = new CloudEvent(
            "/alwayson/reservations",
            "reservation.ready",
            message)
        {
            Subject = message.EventId,
        };

        try
        {
            await senderClient.SendAsync(cloudEvent, cancellationToken);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogError(ex, "Failed to publish reservation-ready event for queue {QueueId}.", message.QueueId);
            throw;
        }
    }
}

/// <summary>
/// No-op notifier used when Event Grid is not configured (integration tests).
/// Captures messages in memory so tests can assert publication.
/// </summary>
internal sealed class NullReservationNotifier : IReservationNotifier
{
    private readonly List<ReservationReadyMessage> _published = [];
    private readonly Lock _lock = new();

    public IReadOnlyList<ReservationReadyMessage> Published
    {
        get
        {
            lock (_lock)
            {
                return _published.ToArray();
            }
        }
    }

    public Task PublishReadyAsync(ReservationReadyMessage message, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(message);
        lock (_lock)
        {
            _published.Add(message);
        }
        return Task.CompletedTask;
    }
}
