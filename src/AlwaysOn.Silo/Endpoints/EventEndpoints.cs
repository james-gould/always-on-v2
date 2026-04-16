using AlwaysOn.Shared.Grains;
using AlwaysOn.Silo.Models;

namespace AlwaysOn.Silo.Endpoints;

public static class EventEndpoints
{
    public static IEndpointRouteBuilder MapEventEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapGet("/events/{eventId}", async (string eventId, IGrainFactory grains) =>
        {
            var grain = grains.GetGrain<IEventGrain>(eventId);
            return Results.Ok(await grain.GetAsync());
        });

        app.MapPost("/events", async (CreateEventRequest request, IGrainFactory grains) =>
        {
            var eventId = string.IsNullOrWhiteSpace(request.EventId)
                ? Guid.NewGuid().ToString("N")
                : request.EventId;

            var grain = grains.GetGrain<IEventGrain>(eventId);
            var saved = await grain.UpsertAsync(request.Name, request.StartsAtUtc, request.Venue, request.Capacity);

            return Results.Created($"/events/{eventId}", saved);
        });

        return app;
    }
}
