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

public sealed class ReservationQueueGrain(
    [PersistentState("reservationQueue", "Default")] IPersistentState<ReservationQueueState> state,
    IGrainFactory grains,
    IQueueIndex queueIndex,
    IReservationNotifier notifier,
    IOptions<ReservationQueueOptions> options,
    ILogger<ReservationQueueGrain> logger,
    TimeProvider timeProvider) : Grain, IReservationQueueGrain, IRemindable
{
    private const string _expirySweepReminder = "reservation-expiry-sweep";

    private readonly ReservationQueueOptions _options = options.Value;

    private string EventId => this.GetPrimaryKeyString();

    public async Task<QueueEntry> EnqueueAsync(string userId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(userId);

        var queueId = Guid.NewGuid().ToString("N");
        var now = timeProvider.GetUtcNow();

        state.State.Waiting.Add(new WaitingEntry(queueId, userId, now));
        await state.WriteStateAsync();

        var eventName = await SafeGetEventNameAsync();

        var entry = new QueueEntry(
            queueId,
            EventId,
            userId,
            now,
            QueueEntryStatus.Waiting,
            state.State.Waiting.Count,
            eventName,
            ReservationExpiresAtUtc: null);

        await queueIndex.WriteAsync(entry, _options.QueueIndexTtl);

        // Promote as many waiters as possible up to the concurrency window.
        await PromoteWaitersAsync(eventName);

        // Ensure the expiry sweep reminder is running.
        await EnsureExpirySweepReminderAsync();

        // Return the most recent view (may already have been promoted if the window was free).
        return (await queueIndex.TryReadAsync(queueId)) ?? entry;
    }

    public async Task ReleaseAsync(string queueId, bool completed)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(queueId);

        if (!state.State.Active.Remove(queueId))
        {
            // Also check waiting — an abandoning user before promotion.
            state.State.Waiting.RemoveAll(w => w.QueueId == queueId);
        }

        await state.WriteStateAsync();

        var existing = await queueIndex.TryReadAsync(queueId);
        if (existing is not null)
        {
            var updated = existing with
            {
                Status = completed ? QueueEntryStatus.Completed : QueueEntryStatus.Expired,
                ReservationExpiresAtUtc = null,
            };
            await queueIndex.WriteAsync(updated, _options.QueueIndexTtl);
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

        var now = timeProvider.GetUtcNow();
        var expired = state.State.Active
            .Where(kvp => kvp.Value.ExpiresAtUtc <= now)
            .Select(kvp => kvp.Value)
            .ToArray();

        if (expired.Length == 0 && state.State.Active.Count == 0 && state.State.Waiting.Count == 0)
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
            state.State.Active.Remove(expiredReservation.QueueId);
            var existing = await queueIndex.TryReadAsync(expiredReservation.QueueId);
            if (existing is not null)
            {
                await queueIndex.WriteAsync(
                    existing with
                    {
                        Status = QueueEntryStatus.Expired,
                        ReservationExpiresAtUtc = null,
                    },
                    _options.QueueIndexTtl);
            }
            logger.LogInformation(
                "Reservation {QueueId} for event {EventId} expired without purchase.",
                expiredReservation.QueueId,
                EventId);
        }

        if (expired.Length > 0)
        {
            await state.WriteStateAsync();
            var eventName = await SafeGetEventNameAsync();
            await PromoteWaitersAsync(eventName);
        }
    }

    private async Task PromoteWaitersAsync(string? eventName)
    {
        var promoted = false;

        while (state.State.Active.Count < _options.ConcurrentReservationWindow
               && state.State.Waiting.Count > 0)
        {
            var next = state.State.Waiting[0];
            state.State.Waiting.RemoveAt(0);

            var expiresAt = timeProvider.GetUtcNow().Add(_options.ReservationTtl);
            state.State.Active[next.QueueId] = new ActiveReservation(
                next.QueueId,
                next.UserId,
                next.EnqueuedAtUtc,
                expiresAt);

            promoted = true;

            var entry = new QueueEntry(
                next.QueueId,
                EventId,
                next.UserId,
                next.EnqueuedAtUtc,
                QueueEntryStatus.Ready,
                Position: 0,
                eventName,
                expiresAt);

            await queueIndex.WriteAsync(entry, _options.QueueIndexTtl);

            try
            {
                await notifier.PublishReadyAsync(new ReservationReadyMessage(
                    next.QueueId,
                    EventId,
                    next.UserId,
                    expiresAt));
            }
            catch (Exception ex)
            {
                logger.LogWarning(
                    ex,
                    "Failed to publish reservation-ready for {QueueId}; Redis mirror still updated so /myqueue will reflect Ready state.",
                    next.QueueId);
            }
        }

        if (promoted)
        {
            await state.WriteStateAsync();
            await RefreshWaitingPositionsAsync(eventName);
        }
    }

    private async Task RefreshWaitingPositionsAsync(string? eventName)
    {
        for (var i = 0; i < state.State.Waiting.Count; i++)
        {
            var waiting = state.State.Waiting[i];

            var entry = new QueueEntry(
                waiting.QueueId,
                EventId,
                waiting.UserId,
                waiting.EnqueuedAtUtc,
                QueueEntryStatus.Waiting,
                i + 1,
                eventName,
                ReservationExpiresAtUtc: null);

            await queueIndex.WriteAsync(entry, _options.QueueIndexTtl);
        }
    }

    private async Task<string?> SafeGetEventNameAsync()
    {
        try
        {
            var details = await grains.GetGrain<IEventGrain>(EventId).GetAsync();
            return details.Name;
        }
        catch (Exception ex)
        {
            logger.LogDebug(ex, "Could not resolve event name for {EventId}.", EventId);
            return null;
        }
    }

    private async Task EnsureExpirySweepReminderAsync()
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
