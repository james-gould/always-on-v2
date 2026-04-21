using System.Text.Json;
using AlwaysOn.Shared.Models;
using Microsoft.Extensions.Options;
using StackExchange.Redis;

namespace AlwaysOn.Silo.Caching;

public sealed class EventReadCacheOptions
{
    /// <summary>Time-to-live for cached event entries.</summary>
    public TimeSpan Ttl { get; set; } = TimeSpan.FromSeconds(60);

    /// <summary>Redis key prefix for cached events.</summary>
    public string KeyPrefix { get; set; } = "event:";
}

/// <summary>
/// Redis-backed implementation of <see cref="IEventReadCache"/>.
/// On a cache miss the loader populates Redis with a short TTL. Mutations
/// (<c>POST /events</c>) call <see cref="InvalidateAsync"/> so the next read
/// repopulates from the grain.
/// </summary>
internal sealed class RedisEventReadCache : IEventReadCache
{
    private static readonly JsonSerializerOptions _jsonOptions = new(JsonSerializerDefaults.Web);

    private readonly IConnectionMultiplexer _redis;
    private readonly EventReadCacheOptions _options;
    private readonly ILogger<RedisEventReadCache> _logger;

    public RedisEventReadCache(
        IConnectionMultiplexer redis,
        IOptions<EventReadCacheOptions> options,
        ILogger<RedisEventReadCache> logger)
    {
        _redis = redis;
        _options = options.Value;
        _logger = logger;
    }

    public async Task<EventDetails> GetOrLoadAsync(string eventId, Func<Task<EventDetails>> loader, CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(eventId);
        ArgumentNullException.ThrowIfNull(loader);

        var key = BuildKey(eventId);
        var db = _redis.GetDatabase();

        try
        {
            var cached = await db.StringGetAsync(key).WaitAsync(cancellationToken).ConfigureAwait(false);
            if (cached.HasValue)
            {
                var hit = JsonSerializer.Deserialize<EventDetails>((string)cached!, _jsonOptions);
                if (hit is not null)
                {
                    return hit;
                }
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogWarning(ex, "Redis read failed for event {EventId}; falling back to grain.", eventId);
        }

        var loaded = await loader().ConfigureAwait(false);

        try
        {
            var payload = JsonSerializer.Serialize(loaded, _jsonOptions);
            await db.StringSetAsync(key, payload, _options.Ttl).WaitAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogWarning(ex, "Redis write failed for event {EventId}; continuing without caching.", eventId);
        }

        return loaded;
    }

    public async Task InvalidateAsync(string eventId, CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(eventId);

        var key = BuildKey(eventId);
        var db = _redis.GetDatabase();

        try
        {
            await db.KeyDeleteAsync(key).WaitAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogWarning(ex, "Redis invalidate failed for event {EventId}.", eventId);
        }
    }

    private string BuildKey(string eventId) => _options.KeyPrefix + eventId;
}
