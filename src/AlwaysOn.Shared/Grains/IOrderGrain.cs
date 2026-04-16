using AlwaysOn.Shared.Models;

namespace AlwaysOn.Shared.Grains;

public interface IOrderGrain : IGrainWithStringKey
{
	Task<OrderDetails> GetAsync();

	Task<OrderDetails> UpsertAsync(string eventId, string userId, IReadOnlyList<string> ticketIds);
}
