namespace AlwaysOn.IntegrationTests.SetupHelper.Models;

internal sealed record IssueTicketRequest(
    string? TicketId,
    string EventId,
    string OrderId,
    string UserId);
