using AlwaysOn.Shared.Grains;
using AlwaysOn.Shared.Models;

namespace AlwaysOn.Silo.Grains;

public class TicketGrain : Grain, ITicketGrain
{
    private readonly IPersistentState<TicketDetails> _ticketState;

    public TicketGrain([PersistentState("ticket", "Default")] IPersistentState<TicketDetails> ticketState)
    {
        _ticketState = ticketState;
    }

    public Task<TicketDetails> GetAsync()
    {
        if (_ticketState.RecordExists)
        {
            return Task.FromResult(_ticketState.State);
        }

        var current = new TicketDetails(
            TicketId: this.GetPrimaryKeyString(),
            EventId: "unknown-event",
            OrderId: "unknown-order",
            UserId: "anonymous-user",
            Status: "stub",
            IssuedAtUtc: DateTimeOffset.UtcNow);

        return Task.FromResult(current);
    }

    public async Task<TicketDetails> IssueAsync(string eventId, string orderId, string userId)
    {
        _ticketState.State = new TicketDetails(
            TicketId: this.GetPrimaryKeyString(),
            EventId: eventId,
            OrderId: orderId,
            UserId: userId,
            Status: "issued",
            IssuedAtUtc: DateTimeOffset.UtcNow);

        await _ticketState.WriteStateAsync();

        return _ticketState.State;
    }
}
