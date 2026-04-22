using AlwaysOn.Shared.Models;

namespace AlwaysOn.Silo.Caching;

/// <summary>
/// Read-through cache for <see cref="EventDetails"/>. Events rarely change
/// once created and <c>GET /events/{id}</c> is the primary high-traffic
/// endpoint, so a short-lived distributed cache eliminates the need to
/// roundtrip through an <c>IEventGrain</c> for every request.
/// </summary>
public interface IEventReadCache
{
    Task<EventDetails> GetOrLoadAsync(string eventId, Func<Task<EventDetails>> loader, CancellationToken cancellationToken = default);

    Task InvalidateAsync(string eventId, CancellationToken cancellationToken = default);
}
