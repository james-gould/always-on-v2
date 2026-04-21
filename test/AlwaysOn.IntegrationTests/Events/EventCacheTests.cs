using System.Net.Http.Json;
using AlwaysOn.IntegrationTests.SetupHelper.Fixtures;
using AlwaysOn.IntegrationTests.SetupHelper.Models;

namespace AlwaysOn.IntegrationTests.Events;

[Collection(AppHostCollection.Name)]
public sealed class EventCacheTests(AppHostTestFixture fixture)
{
    [Fact]
    public async Task PostEventInvalidatesCacheSoGetReturnsLatest()
    {
        var client = await fixture.GetClientAsync();

        var eventId = Guid.NewGuid().ToString("N");

        var first = new CreateEventRequest(
            EventId: eventId,
            Name: "Cache Test v1",
            StartsAtUtc: DateTimeOffset.UtcNow.AddDays(10),
            Venue: "Arena A",
            Capacity: 500);

        (await client.PostAsJsonAsync("/events", first)).EnsureSuccessStatusCode();

        // Prime the cache.
        (await client.GetAsync($"/events/{eventId}")).EnsureSuccessStatusCode();

        var second = new CreateEventRequest(
            EventId: eventId,
            Name: "Cache Test v2",
            StartsAtUtc: DateTimeOffset.UtcNow.AddDays(10),
            Venue: "Arena B",
            Capacity: 750);

        (await client.PostAsJsonAsync("/events", second)).EnsureSuccessStatusCode();

        var refreshed = await client.GetAsync($"/events/{eventId}");
        refreshed.EnsureSuccessStatusCode();

        var body = await refreshed.Content.ReadAsStringAsync();

        Assert.Contains("Cache Test v2", body, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("Arena B", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Cache Test v1", body, StringComparison.OrdinalIgnoreCase);
    }
}
