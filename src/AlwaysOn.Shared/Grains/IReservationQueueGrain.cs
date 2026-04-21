using AlwaysOn.Shared.Models;

namespace AlwaysOn.Shared.Grains;

/// <summary>
/// One grain per event. Acts as the FIFO coordinator for ticket-reservation
/// slots: users enqueue, and the grain promotes them to the "ready" state as
/// slots free up, publishing a message on the reservations Service Bus queue
/// so downstream consumers (SignalR notifier) can push the update.
/// </summary>
public interface IReservationQueueGrain : IGrainWithStringKey
{
    /// <summary>Add a user to the waiting queue.</summary>
    Task<QueueEntry> EnqueueAsync(string userId);

    /// <summary>Release an active reservation back to the pool.</summary>
    /// <param name="queueId">The queue entry identifier.</param>
    /// <param name="completed">If true the entry is recorded as Completed; otherwise as Expired.</param>
    Task ReleaseAsync(string queueId, bool completed);
}
