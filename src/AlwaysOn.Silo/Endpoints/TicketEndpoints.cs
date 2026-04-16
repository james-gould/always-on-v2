using AlwaysOn.Shared.Grains;
using AlwaysOn.Silo.Models;

namespace AlwaysOn.Silo.Endpoints;

public static class TicketEndpoints
{
    public static IEndpointRouteBuilder MapTicketEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapGet("/tickets/{ticketId}", async (string ticketId, IGrainFactory grains) =>
        {
            var grain = grains.GetGrain<ITicketGrain>(ticketId);
            return Results.Ok(await grain.GetAsync());
        });

        app.MapPost("/tickets", async (IssueTicketRequest request, IGrainFactory grains) =>
        {
            var ticketId = string.IsNullOrWhiteSpace(request.TicketId)
                ? Guid.NewGuid().ToString("N")
                : request.TicketId;

            var grain = grains.GetGrain<ITicketGrain>(ticketId);
            var issued = await grain.IssueAsync(request.EventId, request.OrderId, request.UserId);

            return Results.Created($"/tickets/{ticketId}", issued);
        });

        return app;
    }
}
