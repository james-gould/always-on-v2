namespace AlwaysOn.Shared.Models;

[GenerateSerializer]
public sealed record TicketDetails(
    [property: Id(0)] string TicketId,
    [property: Id(1)] string EventId,
    [property: Id(2)] string OrderId,
    [property: Id(3)] string UserId,
    [property: Id(4)] string Status,
    [property: Id(5)] DateTimeOffset IssuedAtUtc);
