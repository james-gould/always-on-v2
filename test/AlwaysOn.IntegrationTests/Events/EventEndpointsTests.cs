using System.Net.Http.Json;
using AlwaysOn.IntegrationTests.SetupHelper.Fixtures;
using AlwaysOn.IntegrationTests.SetupHelper.Models;

namespace AlwaysOn.IntegrationTests.Events;

[Collection(AppHostCollection.Name)]
public sealed class EventEndpointsTests(AppHostTestFixture fixture)
{
    [Fact]
    public async Task PostEventThenGetEventReturnsCreatedPayload()
    {
        var client = await fixture.GetClientAsync();

        var eventId = Guid.NewGuid().ToString("N");
        var request = new CreateEventRequest(
            EventId: eventId,
            Name: "Integration Test Event",
            StartsAtUtc: DateTimeOffset.UtcNow.AddDays(10),
            Venue: "Arena A",
            Capacity: 1000);

        var postResponse = await client.PostAsJsonAsync("/events", request);

        postResponse.EnsureSuccessStatusCode();

        var getResponse = await client.GetAsync($"/events/{eventId}");

        getResponse.EnsureSuccessStatusCode();

        var body = await getResponse.Content.ReadAsStringAsync();

        Assert.Contains(eventId, body, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("Integration Test Event", body, StringComparison.OrdinalIgnoreCase);
    }
}
