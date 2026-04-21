using System.Text.Json;
using AlwaysOn.Shared.Constants;
using Azure.Messaging.ServiceBus;

namespace AlwaysOn.Silo.Queueing;

internal sealed class ServiceBusReservationNotifier(
    ServiceBusClient client,
    ILogger<ServiceBusReservationNotifier> logger) : IReservationNotifier, IAsyncDisposable
{
    private static readonly JsonSerializerOptions _jsonOptions = new(JsonSerializerDefaults.Web);

    private readonly ServiceBusSender _sender = client.CreateSender(AspireConstants.ReservationsQueue);

    public async Task PublishReadyAsync(ReservationReadyMessage message, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(message);

        var payload = JsonSerializer.Serialize(message, _jsonOptions);
        var sbMessage = new ServiceBusMessage(payload)
        {
            ContentType = "application/json",
            Subject = "reservation.ready",
            // ApplicationProperties indexes enable subscription filters for fan-out if we
            // later switch to a topic; keeping the per-event property for traceability.
            ApplicationProperties =
            {
                ["eventId"] = message.EventId,
                ["userId"] = message.UserId,
            },
        };

        try
        {
            await _sender.SendMessageAsync(sbMessage, cancellationToken);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogError(ex, "Failed to publish reservation-ready message for queue {QueueId}.", message.QueueId);
            throw;
        }
    }

    public ValueTask DisposeAsync() => _sender.DisposeAsync();
}

/// <summary>
/// No-op notifier used when Service Bus is not configured (integration tests).
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
