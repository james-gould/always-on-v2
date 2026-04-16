namespace AlwaysOn.Shared.Models;

public sealed record EventDetails(
    string EventId,
    string Name,
    DateTimeOffset StartsAtUtc,
    string Venue,
    int Capacity);
