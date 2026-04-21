using System.Collections.Concurrent;
using System.Text.Json;
using AlwaysOn.Shared.Models;
using StackExchange.Redis;

namespace AlwaysOn.Silo.Queueing;

internal sealed class RedisQueueIndex(IConnectionMultiplexer redis, ILogger<RedisQueueIndex> logger) : IQueueIndex
{
    private const string _keyPrefix = "queue:";
    private static readonly JsonSerializerOptions _jsonOptions = new(JsonSerializerDefaults.Web);

    public async Task WriteAsync(QueueEntry entry, TimeSpan ttl, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(entry);

        var key = _keyPrefix + entry.QueueId;
        var payload = JsonSerializer.Serialize(entry, _jsonOptions);

        try
        {
            await redis.GetDatabase().StringSetAsync(key, payload, ttl).WaitAsync(cancellationToken);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Failed to write queue entry {QueueId} to Redis.", entry.QueueId);
        }
    }

    public async Task<QueueEntry?> TryReadAsync(string queueId, CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(queueId);

        var key = _keyPrefix + queueId;
        try
        {
            var value = await redis.GetDatabase().StringGetAsync(key).WaitAsync(cancellationToken);
            if (value.IsNullOrEmpty)
            {
                return null;
            }

            var bytes = (ReadOnlyMemory<byte>)value;
            return JsonSerializer.Deserialize<QueueEntry>(bytes.Span, _jsonOptions);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Failed to read queue entry {QueueId} from Redis.", queueId);
            return null;
        }
    }

    public async Task RemoveAsync(string queueId, CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(queueId);

        try
        {
            await redis.GetDatabase().KeyDeleteAsync(_keyPrefix + queueId).WaitAsync(cancellationToken);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Failed to delete queue entry {QueueId} from Redis.", queueId);
        }
    }
}

/// <summary>
/// Process-local fallback used when Redis is not wired up (e.g. integration
/// tests). Mirrors <see cref="RedisQueueIndex"/> semantics sufficiently for
/// endpoints and grains to remain agnostic.
/// </summary>
internal sealed class InMemoryQueueIndex : IQueueIndex
{
    private sealed record Entry(QueueEntry Value, DateTimeOffset ExpiresAtUtc);

    private readonly ConcurrentDictionary<string, Entry> _entries = new();

    public Task WriteAsync(QueueEntry entry, TimeSpan ttl, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(entry);
        _entries[entry.QueueId] = new Entry(entry, DateTimeOffset.UtcNow.Add(ttl));
        return Task.CompletedTask;
    }

    public Task<QueueEntry?> TryReadAsync(string queueId, CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(queueId);
        if (_entries.TryGetValue(queueId, out var entry))
        {
            if (entry.ExpiresAtUtc > DateTimeOffset.UtcNow)
            {
                return Task.FromResult<QueueEntry?>(entry.Value);
            }

            _entries.TryRemove(queueId, out _);
        }

        return Task.FromResult<QueueEntry?>(null);
    }

    public Task RemoveAsync(string queueId, CancellationToken cancellationToken = default)
    {
        _entries.TryRemove(queueId, out _);
        return Task.CompletedTask;
    }
}
