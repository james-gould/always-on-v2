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
internal sealed class RedisEventReadCache(
    Lazy<Task<IConnectionMultiplexer>> redisFactory,
    IOptions<EventReadCacheOptions> options,
    ILogger<RedisEventReadCache> logger) : IEventReadCache
{
    private static readonly JsonSerializerOptions _jsonOptions = new(JsonSerializerDefaults.Web);

    private readonly EventReadCacheOptions _options = options.Value;

    public async Task<EventDetails> GetOrLoadAsync(string eventId, Func<Task<EventDetails>> loader, CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(eventId);
        ArgumentNullException.ThrowIfNull(loader);

        var key = BuildKey(eventId);
        var redis = await redisFactory.Value;
        var db = redis.GetDatabase();

        try
        {
            var cached = await db.StringGetAsync(key).WaitAsync(cancellationToken);
            if (TryDeserialize(cached, out var hit))
            {
                return hit;
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Redis read failed for event {EventId}; falling back to grain.", eventId);
        }

        var loaded = await loader();

        try
        {
            var payload = JsonSerializer.Serialize(loaded, _jsonOptions);
            await db.StringSetAsync(key, payload, _options.Ttl).WaitAsync(cancellationToken);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Redis write failed for event {EventId}; continuing without caching.", eventId);
        }

        return loaded;
    }

    public async Task InvalidateAsync(string eventId, CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(eventId);

        try
        {
            var redis = await redisFactory.Value;
            await redis.GetDatabase().KeyDeleteAsync(BuildKey(eventId)).WaitAsync(cancellationToken);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Redis invalidate failed for event {EventId}.", eventId);
        }
    }

    private string BuildKey(string eventId) => _options.KeyPrefix + eventId;

    private static bool TryDeserialize(RedisValue value, out EventDetails result)
    {
        result = default!;

        if (value.IsNullOrEmpty)
        {
            return false;
        }

        // RedisValue implicitly converts to ReadOnlyMemory<byte>, avoiding an
        // unnecessary string allocation and the c-style cast.
        var bytes = (ReadOnlyMemory<byte>)value;
        var parsed = JsonSerializer.Deserialize<EventDetails>(bytes.Span, _jsonOptions);
        if (parsed is null)
        {
            return false;
        }

        result = parsed;
        return true;
    }
}
