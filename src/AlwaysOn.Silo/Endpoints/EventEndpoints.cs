using AlwaysOn.Shared.Grains;
using AlwaysOn.Silo.Caching;
using AlwaysOn.Silo.Models;

namespace AlwaysOn.Silo.Endpoints;

public static class EventEndpoints
{
    public static IEndpointRouteBuilder MapEventEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapGet("/events/{eventId}", async (string eventId, IGrainFactory grains, IEventReadCache cache, CancellationToken ct) =>
        {
            var details = await cache.GetOrLoadAsync(
                eventId,
                () => grains.GetGrain<IEventGrain>(eventId).GetAsync(),
                ct);

            return Results.Ok(details);
        });

        app.MapPost("/events", async (CreateEventRequest request, IGrainFactory grains, IEventReadCache cache, CancellationToken ct) =>
        {
            var eventId = string.IsNullOrWhiteSpace(request.EventId)
                ? Guid.NewGuid().ToString("N")
                : request.EventId;

            var grain = grains.GetGrain<IEventGrain>(eventId);
            var saved = await grain.UpsertAsync(request.Name, request.StartsAtUtc, request.Venue, request.Capacity);

            // Invalidate so subsequent GETs see the new data rather than a stale cache hit.
            await cache.InvalidateAsync(eventId, ct);

            return Results.Created($"/events/{eventId}", saved);
        });

        return app;
    }
}
