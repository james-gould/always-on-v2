namespace AlwaysOn.Silo.Models;

public sealed record CreateEventRequest(
    string? EventId,
    string Name,
    DateTimeOffset StartsAtUtc,
    string Venue,
    int Capacity);
