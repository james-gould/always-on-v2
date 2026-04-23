using System.Collections.Concurrent;
using AlwaysOn.Shared.Models;

namespace AlwaysOn.Silo.Caching;

/// <summary>
/// In-process fallback cache used when Redis is not configured (e.g. the
/// in-memory integration-test mode). Behaviour mirrors the Redis implementation
/// well enough that endpoints don't need to branch.
/// </summary>
internal sealed class InMemoryEventReadCache(TimeSpan ttl) : IEventReadCache
{
    private sealed record Entry(EventDetails Value, DateTimeOffset ExpiresAtUtc);

    private readonly ConcurrentDictionary<string, Entry> _entries = new();
    private readonly TimeSpan _ttl = ttl;

    public InMemoryEventReadCache() : this(TimeSpan.FromSeconds(60))
    {
    }

    public async Task<EventDetails> GetOrLoadAsync(string eventId, Func<Task<EventDetails>> loader, CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(eventId);
        ArgumentNullException.ThrowIfNull(loader);

        if (_entries.TryGetValue(eventId, out var entry) && entry.ExpiresAtUtc > DateTimeOffset.UtcNow)
        {
            return entry.Value;
        }

        var loaded = await loader().ConfigureAwait(false);
        _entries[eventId] = new Entry(loaded, DateTimeOffset.UtcNow.Add(_ttl));
        return loaded;
    }

    public Task InvalidateAsync(string eventId, CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(eventId);
        _entries.TryRemove(eventId, out _);
        return Task.CompletedTask;
    }
}
