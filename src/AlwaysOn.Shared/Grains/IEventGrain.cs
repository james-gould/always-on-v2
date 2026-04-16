using AlwaysOn.Shared.Models;

namespace AlwaysOn.Shared.Grains;

public interface IEventGrain : IGrainWithStringKey
{
    Task<EventDetails> GetAsync();

    Task<EventDetails> UpsertAsync(string name, DateTimeOffset startsAtUtc, string venue, int capacity);
}
