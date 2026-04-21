using AlwaysOn.Shared.Grains;
using AlwaysOn.Shared.Models;
using AlwaysOn.Silo.Queueing;
using Microsoft.Extensions.Options;

namespace AlwaysOn.Silo.Grains;

public sealed class ReservationQueueOptions
{
    /// <summary>
    /// Per-event cap on concurrent ready (reserved-but-not-purchased) slots.
    /// Total tickets are still guarded by the event capacity, but this value
    /// shapes the flow so a huge waiting cohort drains in controlled waves
    /// rather than being promoted all at once.
    /// </summary>
    public int ConcurrentReservationWindow { get; set; } = 50;

    /// <summary>How long a user has to complete purchase before the slot returns to the pool.</summary>
    public TimeSpan ReservationTtl { get; set; } = TimeSpan.FromMinutes(3);

    /// <summary>TTL for queue-entry mirror in Redis (covers the entire queue lifetime).</summary>
    public TimeSpan QueueIndexTtl { get; set; } = TimeSpan.FromHours(2);
}

[GenerateSerializer]
public sealed class ReservationQueueState
{
    /// <summary>FIFO of queue ids waiting for a slot.</summary>
    [Id(0)] public List<WaitingEntry> Waiting { get; set; } = [];

    /// <summary>Currently active reservations keyed by queue id.</summary>
    [Id(1)] public Dictionary<string, ActiveReservation> Active { get; set; } = [];
}

[GenerateSerializer]
public sealed record WaitingEntry(
    [property: Id(0)] string QueueId,
    [property: Id(1)] string UserId,
    [property: Id(2)] DateTimeOffset EnqueuedAtUtc);

[GenerateSerializer]
public sealed record ActiveReservation(
    [property: Id(0)] string QueueId,
    [property: Id(1)] string UserId,
    [property: Id(2)] DateTimeOffset EnqueuedAtUtc,
    [property: Id(3)] DateTimeOffset ExpiresAtUtc);

public sealed class ReservationQueueGrain : Grain, IReservationQueueGrain, IRemindable
{
    private const string _expirySweepReminder = "reservation-expiry-sweep";

    private readonly IPersistentState<ReservationQueueState> _state;
    private readonly IGrainFactory _grains;
    private readonly IQueueIndex _queueIndex;
    private readonly IReservationNotifier _notifier;
    private readonly ReservationQueueOptions _options;
    private readonly ILogger<ReservationQueueGrain> _logger;
    private readonly TimeProvider _timeProvider;

    public ReservationQueueGrain(
        [PersistentState("reservationQueue", "Default")] IPersistentState<ReservationQueueState> state,
        IGrainFactory grains,
        IQueueIndex queueIndex,
        IReservationNotifier notifier,
        IOptions<ReservationQueueOptions> options,
        ILogger<ReservationQueueGrain> logger,
        TimeProvider timeProvider)
    {
        _state = state;
        _grains = grains;
        _queueIndex = queueIndex;
        _notifier = notifier;
        _options = options.Value;
        _logger = logger;
        _timeProvider = timeProvider;
    }

    private string EventId => this.GetPrimaryKeyString();

    public async Task<QueueEntry> EnqueueAsync(string userId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(userId);

        var queueId = Guid.NewGuid().ToString("N");
        var now = _timeProvider.GetUtcNow();

        _state.State.Waiting.Add(new WaitingEntry(queueId, userId, now));
        await _state.WriteStateAsync();

        var eventName = await SafeGetEventNameAsync();

        var initialPosition = ComputePosition(queueId);

        var entry = new QueueEntry(
            QueueId: queueId,
            EventId: EventId,
            UserId: userId,
            EnqueuedAtUtc: now,
            Status: QueueEntryStatus.Waiting,
            Position: initialPosition,
            EventName: eventName,
            ReservationExpiresAtUtc: null);

        await _queueIndex.WriteAsync(entry, _options.QueueIndexTtl);

        // Promote as many waiters as possible up to the concurrency window.
        await PromoteWaitersAsync(eventName);

        // Ensure the expiry sweep reminder is running.
        await Ensure_expirySweepReminderAsync();

        // Return the most recent view (may already have been promoted if the window was free).
        return (await _queueIndex.TryReadAsync(queueId)) ?? entry;
    }

    public async Task ReleaseAsync(string queueId, bool completed)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(queueId);

        if (!_state.State.Active.Remove(queueId))
        {
            // Also check waiting — an abandoning user before promotion.
            _state.State.Waiting.RemoveAll(w => w.QueueId == queueId);
        }

        await _state.WriteStateAsync();

        var existing = await _queueIndex.TryReadAsync(queueId);
        if (existing is not null)
        {
            var updated = existing with
            {
                Status = completed ? QueueEntryStatus.Completed : QueueEntryStatus.Expired,
                ReservationExpiresAtUtc = null,
            };
            await _queueIndex.WriteAsync(updated, _options.QueueIndexTtl);
        }

        var eventName = await SafeGetEventNameAsync();
        await PromoteWaitersAsync(eventName);
    }

    public async Task ReceiveReminder(string reminderName, TickStatus status)
    {
        if (!string.Equals(reminderName, _expirySweepReminder, StringComparison.Ordinal))
        {
            return;
        }

        var now = _timeProvider.GetUtcNow();
        var expired = _state.State.Active
            .Where(kvp => kvp.Value.ExpiresAtUtc <= now)
            .Select(kvp => kvp.Value)
            .ToArray();

        if (expired.Length == 0 && _state.State.Active.Count == 0 && _state.State.Waiting.Count == 0)
        {
            // Nothing to do — tear down the reminder to avoid perpetual activations.
            var reminder = await this.GetReminder(_expirySweepReminder);
            if (reminder is not null)
            {
                await this.UnregisterReminder(reminder);
            }
            return;
        }

        foreach (var expiredReservation in expired)
        {
            _state.State.Active.Remove(expiredReservation.QueueId);
            var existing = await _queueIndex.TryReadAsync(expiredReservation.QueueId);
            if (existing is not null)
            {
                await _queueIndex.WriteAsync(
                    existing with
                    {
                        Status = QueueEntryStatus.Expired,
                        ReservationExpiresAtUtc = null,
                    },
                    _options.QueueIndexTtl);
            }
            _logger.LogInformation(
                "Reservation {QueueId} for event {EventId} expired without purchase.",
                expiredReservation.QueueId,
                EventId);
        }

        if (expired.Length > 0)
        {
            await _state.WriteStateAsync();
            var eventName = await SafeGetEventNameAsync();
            await PromoteWaitersAsync(eventName);
        }
    }

    private async Task PromoteWaitersAsync(string? eventName)
    {
        var promoted = false;

        while (_state.State.Active.Count < _options.ConcurrentReservationWindow
               && _state.State.Waiting.Count > 0)
        {
            var next = _state.State.Waiting[0];
            _state.State.Waiting.RemoveAt(0);

            var expiresAt = _timeProvider.GetUtcNow().Add(_options.ReservationTtl);
            _state.State.Active[next.QueueId] = new ActiveReservation(
                next.QueueId,
                next.UserId,
                next.EnqueuedAtUtc,
                expiresAt);

            promoted = true;

            var entry = new QueueEntry(
                QueueId: next.QueueId,
                EventId: EventId,
                UserId: next.UserId,
                EnqueuedAtUtc: next.EnqueuedAtUtc,
                Status: QueueEntryStatus.Ready,
                Position: 0,
                EventName: eventName,
                ReservationExpiresAtUtc: expiresAt);

            await _queueIndex.WriteAsync(entry, _options.QueueIndexTtl);

            try
            {
                await _notifier.PublishReadyAsync(new ReservationReadyMessage(
                    next.QueueId,
                    EventId,
                    next.UserId,
                    expiresAt));
            }
            catch (Exception ex)
            {
                _logger.LogWarning(
                    ex,
                    "Failed to publish reservation-ready for {QueueId}; Redis mirror still updated so /myqueue will reflect Ready state.",
                    next.QueueId);
            }
        }

        if (promoted)
        {
            await _state.WriteStateAsync();
            await RefreshWaitingPositionsAsync(eventName);
        }
    }

    private async Task RefreshWaitingPositionsAsync(string? eventName)
    {
        for (var i = 0; i < _state.State.Waiting.Count; i++)
        {
            var waiting = _state.State.Waiting[i];
            var entry = new QueueEntry(
                QueueId: waiting.QueueId,
                EventId: EventId,
                UserId: waiting.UserId,
                EnqueuedAtUtc: waiting.EnqueuedAtUtc,
                Status: QueueEntryStatus.Waiting,
                Position: i + 1,
                EventName: eventName,
                ReservationExpiresAtUtc: null);

            await _queueIndex.WriteAsync(entry, _options.QueueIndexTtl);
        }
    }

    private int ComputePosition(string queueId)
    {
        for (var i = 0; i < _state.State.Waiting.Count; i++)
        {
            if (_state.State.Waiting[i].QueueId == queueId)
            {
                return i + 1;
            }
        }
        return 0;
    }

    private async Task<string?> SafeGetEventNameAsync()
    {
        try
        {
            var details = await _grains.GetGrain<IEventGrain>(EventId).GetAsync();
            return details.Name;
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Could not resolve event name for {EventId}.", EventId);
            return null;
        }
    }

    private async Task Ensure_expirySweepReminderAsync()
    {
        var existing = await this.GetReminder(_expirySweepReminder);
        if (existing is not null)
        {
            return;
        }

        // Orleans requires reminder period >= 1 minute. Run every minute so a
        // 3-minute reservation is reclaimed within a minute of expiry.
        await this.RegisterOrUpdateReminder(
            _expirySweepReminder,
            dueTime: TimeSpan.FromMinutes(1),
            period: TimeSpan.FromMinutes(1));
    }
}
