using AlwaysOn.Shared.Models;

namespace AlwaysOn.Shared.Grains;

public interface ITicketGrain : IGrainWithStringKey
{
    Task<TicketDetails> GetAsync();

    Task<TicketDetails> IssueAsync(string eventId, string orderId, string userId);
}
