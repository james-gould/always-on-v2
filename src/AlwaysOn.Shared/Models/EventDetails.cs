namespace AlwaysOn.Shared.Models;

[GenerateSerializer]
public sealed record EventDetails(
    [property: Id(0)] string EventId,
    [property: Id(1)] string Name,
    [property: Id(2)] DateTimeOffset StartsAtUtc,
    [property: Id(3)] string Venue,
    [property: Id(4)] int Capacity);
