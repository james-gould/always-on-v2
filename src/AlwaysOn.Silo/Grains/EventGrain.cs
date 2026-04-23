using AlwaysOn.Shared.Grains;
using AlwaysOn.Shared.Models;

namespace AlwaysOn.Silo.Grains;

public class EventGrain([PersistentState("event", "Default")] IPersistentState<EventDetails> eventState) : Grain, IEventGrain
{
	private readonly IPersistentState<EventDetails> _eventState = eventState;

    public Task<EventDetails> GetAsync()
	{
		if (_eventState.RecordExists)
		{
			return Task.FromResult(_eventState.State);
		}

		var current = new EventDetails(
			EventId: this.GetPrimaryKeyString(),
			Name: "Stub Event",
			StartsAtUtc: DateTimeOffset.UtcNow.AddDays(14),
			Venue: "Main Hall",
			Capacity: 250);

		return Task.FromResult(current);
	}

	public async Task<EventDetails> UpsertAsync(string name, DateTimeOffset startsAtUtc, string venue, int capacity)
	{
		_eventState.State = new EventDetails(
			EventId: this.GetPrimaryKeyString(),
			Name: name,
			StartsAtUtc: startsAtUtc,
			Venue: venue,
			Capacity: capacity);

		await _eventState.WriteStateAsync();

		return _eventState.State;
	}
}
