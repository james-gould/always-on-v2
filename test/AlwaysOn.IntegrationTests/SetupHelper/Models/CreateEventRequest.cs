namespace AlwaysOn.IntegrationTests.SetupHelper.Models;

internal sealed record CreateEventRequest(
    string? EventId,
    string Name,
    DateTimeOffset StartsAtUtc,
    string Venue,
    int Capacity);
