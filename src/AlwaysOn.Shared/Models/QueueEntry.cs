namespace AlwaysOn.Shared.Models;

/// <summary>
/// Lifecycle states for a queue entry backing the ticket-reservation flow.
/// </summary>
public enum QueueEntryStatus
{
    /// <summary>The user is waiting for a slot.</summary>
    Waiting = 0,

    /// <summary>The slot has been assigned; the user has a limited time to complete purchase.</summary>
    Ready = 1,

    /// <summary>The reservation window elapsed without purchase.</summary>
    Expired = 2,

    /// <summary>The user completed the purchase.</summary>
    Completed = 3,
}

[GenerateSerializer]
public sealed record QueueEntry(
    [property: Id(0)] string QueueId,
    [property: Id(1)] string EventId,
    [property: Id(2)] string UserId,
    [property: Id(3)] DateTimeOffset EnqueuedAtUtc,
    [property: Id(4)] QueueEntryStatus Status,
    [property: Id(5)] int Position,
    [property: Id(6)] string? EventName,
    [property: Id(7)] DateTimeOffset? ReservationExpiresAtUtc);
