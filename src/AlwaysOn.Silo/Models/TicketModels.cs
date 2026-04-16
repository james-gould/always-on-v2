namespace AlwaysOn.Silo.Models;

public sealed record IssueTicketRequest(
    string? TicketId,
    string EventId,
    string OrderId,
    string UserId);
