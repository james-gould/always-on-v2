namespace AlwaysOn.IntegrationTests.SetupHelper.Models;

internal sealed record CreateOrderRequest(
    string? OrderId,
    string EventId,
    string UserId,
    int TicketQuantity);
