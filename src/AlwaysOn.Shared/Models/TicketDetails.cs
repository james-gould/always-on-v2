namespace AlwaysOn.Shared.Models;

public sealed record TicketDetails(
    string TicketId,
    string EventId,
    string OrderId,
    string UserId,
    string Status,
    DateTimeOffset IssuedAtUtc);
