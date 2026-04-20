using AlwaysOn.Shared.Grains;
using AlwaysOn.Shared.Models;
using AlwaysOn.Silo.Models;

namespace AlwaysOn.Silo.Endpoints;

public static class OrderEndpoints
{
    public static IEndpointRouteBuilder MapOrderEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapGet("/orders/{orderId}", async (string orderId, IGrainFactory grains) =>
        {
            var grain = grains.GetGrain<IOrderGrain>(orderId);
            return Results.Ok(await grain.GetAsync());
        });

        app.MapPost("/orders", async (CreateOrderRequest request, IGrainFactory grains) =>
        {
            if (request.TicketQuantity <= 0)
            {
                return Results.BadRequest("TicketQuantity must be greater than zero.");
            }

            var orderId = string.IsNullOrWhiteSpace(request.OrderId)
                ? Guid.NewGuid().ToString("N")
                : request.OrderId;

            var issuedTickets = new List<TicketDetails>(request.TicketQuantity);
            var ticketIds = new List<string>(request.TicketQuantity);

            for (var i = 0; i < request.TicketQuantity; i++)
            {
                var ticketId = Guid.NewGuid().ToString("N");
                var ticket = await grains.GetGrain<ITicketGrain>(ticketId)
                    .IssueAsync(request.EventId, orderId, request.UserId);

                issuedTickets.Add(ticket);
                ticketIds.Add(ticketId);
            }

            var order = await grains.GetGrain<IOrderGrain>(orderId)
                .UpsertAsync(request.EventId, request.UserId, ticketIds);

            var response = new CreateOrderResponse(order, issuedTickets);
            return Results.Created($"/orders/{orderId}", response);
        });

        return app;
    }
}
