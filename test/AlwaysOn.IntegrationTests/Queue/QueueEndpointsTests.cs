using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using AlwaysOn.IntegrationTests.SetupHelper.Fixtures;
using AlwaysOn.IntegrationTests.SetupHelper.Models;

namespace AlwaysOn.IntegrationTests.Queue;

[Collection(AppHostCollection.Name)]
public sealed class QueueEndpointsTests(AppHostTestFixture fixture)
{
    private static readonly JsonSerializerOptions _jsonOptions = new(JsonSerializerDefaults.Web);

    [Fact]
    public async Task EnqueueUserReturnsQueueEntryAndMyQueueReflectsIt()
    {
        var client = await fixture.GetClientAsync();

        var eventId = Guid.NewGuid().ToString("N");
        var createEvent = new CreateEventRequest(eventId, "Queue Test Event", DateTimeOffset.UtcNow.AddDays(30), "Arena Q", 500);
        (await client.PostAsJsonAsync("/events", createEvent)).EnsureSuccessStatusCode();

        var userId = Guid.NewGuid().ToString("N");
        var enqueue = await client.PostAsJsonAsync($"/events/{eventId}/queue", new { userId });
        enqueue.EnsureSuccessStatusCode();

        var entry = await enqueue.Content.ReadFromJsonAsync<QueueEntryDto>(_jsonOptions);
        Assert.NotNull(entry);
        Assert.Equal(eventId, entry!.EventId);
        Assert.Equal(userId, entry.UserId);
        Assert.False(string.IsNullOrWhiteSpace(entry.QueueId));

        var get = await client.GetAsync($"/myqueue/{entry.QueueId}");
        get.EnsureSuccessStatusCode();
        var snapshot = await get.Content.ReadFromJsonAsync<QueueEntryDto>(_jsonOptions);
        Assert.NotNull(snapshot);
        Assert.Equal(entry.QueueId, snapshot!.QueueId);
    }

    [Fact]
    public async Task ReleaseAsCompletedMarksQueueEntryCompleted()
    {
        var client = await fixture.GetClientAsync();

        var eventId = Guid.NewGuid().ToString("N");
        (await client.PostAsJsonAsync("/events", new CreateEventRequest(eventId, "Release Test", DateTimeOffset.UtcNow.AddDays(7), "Arena R", 200))).EnsureSuccessStatusCode();

        var enqueue = await client.PostAsJsonAsync($"/events/{eventId}/queue", new { userId = "user-r" });
        var entry = await enqueue.Content.ReadFromJsonAsync<QueueEntryDto>(_jsonOptions);
        Assert.NotNull(entry);

        var release = await client.PostAsJsonAsync($"/myqueue/{entry!.QueueId}/release", new { completed = true });
        release.EnsureSuccessStatusCode();

        var snapshot = await release.Content.ReadFromJsonAsync<QueueEntryDto>(_jsonOptions);
        Assert.NotNull(snapshot);
        Assert.Equal(3, snapshot!.Status); // Completed = 3
    }

    [Fact]
    public async Task UnknownQueueIdReturnsNotFound()
    {
        var client = await fixture.GetClientAsync();

        var response = await client.GetAsync($"/myqueue/{Guid.NewGuid():N}");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    private sealed record QueueEntryDto(
        string QueueId,
        string EventId,
        string UserId,
        DateTimeOffset EnqueuedAtUtc,
        int Status,
        int Position,
        string? EventName,
        DateTimeOffset? ReservationExpiresAtUtc);
}
