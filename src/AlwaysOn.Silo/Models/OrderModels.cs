using AlwaysOn.Shared.Models;

namespace AlwaysOn.Silo.Models;

public sealed record CreateOrderRequest(
    string? OrderId,
    string EventId,
    string UserId,
    int TicketQuantity);

public sealed record CreateOrderResponse(
    OrderDetails Order,
    IReadOnlyList<TicketDetails> Tickets);
