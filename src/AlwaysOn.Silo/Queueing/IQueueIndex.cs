using AlwaysOn.Shared.Models;

namespace AlwaysOn.Silo.Queueing;

/// <summary>
/// Redis-backed read model for the reservation queue. The grain is the source
/// of truth for FIFO order and reservation state, but Redis holds a mirror so
/// the <c>GET /myqueue/{id}</c> endpoint can respond without activating the
/// event grain for every poll.
/// </summary>
public interface IQueueIndex
{
    /// <summary>Write a queue entry into the index, replacing any prior value.</summary>
    Task WriteAsync(QueueEntry entry, TimeSpan ttl, CancellationToken cancellationToken = default);

    /// <summary>Read a queue entry by queue id.</summary>
    Task<QueueEntry?> TryReadAsync(string queueId, CancellationToken cancellationToken = default);

    /// <summary>Remove a queue entry.</summary>
    Task RemoveAsync(string queueId, CancellationToken cancellationToken = default);
}
