namespace AlwaysOn.Shared.Models;

[GenerateSerializer]
public sealed record OrderDetails(
    [property: Id(0)] string OrderId,
    [property: Id(1)] string EventId,
    [property: Id(2)] string UserId,
    [property: Id(3)] string Status,
    [property: Id(4)] DateTimeOffset CreatedAtUtc,
    [property: Id(5)] IReadOnlyList<string> TicketIds);
