namespace AlwaysOn.Shared.Models;

public sealed record OrderDetails(
    string OrderId,
    string EventId,
    string UserId,
    string Status,
    DateTimeOffset CreatedAtUtc,
    IReadOnlyList<string> TicketIds);
