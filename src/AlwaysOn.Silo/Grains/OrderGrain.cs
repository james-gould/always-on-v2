using AlwaysOn.Shared.Grains;
using AlwaysOn.Shared.Models;

namespace AlwaysOn.Silo.Grains;

public class OrderGrain([PersistentState("order", "Default")] IPersistentState<OrderDetails> orderState) : Grain, IOrderGrain
{
	private readonly IPersistentState<OrderDetails> _orderState = orderState;

    public Task<OrderDetails> GetAsync()
	{
		if (_orderState.RecordExists)
		{
			return Task.FromResult(_orderState.State);
		}

		var current = new OrderDetails(
			OrderId: this.GetPrimaryKeyString(),
			EventId: "unknown-event",
			UserId: "anonymous-user",
			Status: "stub",
			CreatedAtUtc: DateTimeOffset.UtcNow,
			TicketIds: Array.Empty<string>());

		return Task.FromResult(current);
	}

	public async Task<OrderDetails> UpsertAsync(string eventId, string userId, IReadOnlyList<string> ticketIds)
	{
		_orderState.State = new OrderDetails(
			OrderId: this.GetPrimaryKeyString(),
			EventId: eventId,
			UserId: userId,
			Status: "created",
			CreatedAtUtc: DateTimeOffset.UtcNow,
			TicketIds: ticketIds.ToList());

		await _orderState.WriteStateAsync();

		return _orderState.State;
	}
}
