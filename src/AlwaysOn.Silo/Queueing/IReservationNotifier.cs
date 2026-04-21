namespace AlwaysOn.Silo.Queueing;

/// <summary>
/// Payload published to the reservations queue when a user is promoted from
/// Waiting to Ready. The downstream consumer (SignalR notifier) uses this to
/// push the event to the correct per-user channel.
/// </summary>
[GenerateSerializer]
public sealed record ReservationReadyMessage(
    [property: Id(0)] string QueueId,
    [property: Id(1)] string EventId,
    [property: Id(2)] string UserId,
    [property: Id(3)] DateTimeOffset ReservationExpiresAtUtc);

public interface IReservationNotifier
{
    Task PublishReadyAsync(ReservationReadyMessage message, CancellationToken cancellationToken = default);
}
