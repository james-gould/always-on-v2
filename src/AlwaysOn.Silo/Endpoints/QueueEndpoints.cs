using AlwaysOn.Shared.Grains;
using AlwaysOn.Silo.Queueing;

namespace AlwaysOn.Silo.Endpoints;

public static class QueueEndpoints
{
    public static IEndpointRouteBuilder MapQueueEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapPost("/events/{eventId}/queue", async (
            string eventId,
            EnqueueRequest request,
            IGrainFactory grains) =>
        {
            if (string.IsNullOrWhiteSpace(eventId))
            {
                return Results.BadRequest("eventId is required.");
            }

            if (string.IsNullOrWhiteSpace(request?.UserId))
            {
                return Results.BadRequest("userId is required.");
            }

            var grain = grains.GetGrain<IReservationQueueGrain>(eventId);
            var entry = await grain.EnqueueAsync(request.UserId);
            return Results.Created($"/myqueue/{entry.QueueId}", entry);
        });

        app.MapGet("/myqueue/{queueId}", async (string queueId, IQueueIndex index) =>
        {
            if (string.IsNullOrWhiteSpace(queueId))
            {
                return Results.BadRequest("queueId is required.");
            }

            var entry = await index.TryReadAsync(queueId);
            if (entry is null)
            {
                return Results.NotFound();
            }

            return Results.Ok(entry);
        });

        app.MapPost("/myqueue/{queueId}/release", async (
            string queueId,
            ReleaseReservationRequest? body,
            IGrainFactory grains,
            IQueueIndex index) =>
        {
            var existing = await index.TryReadAsync(queueId);
            if (existing is null)
            {
                return Results.NotFound();
            }

            var grain = grains.GetGrain<IReservationQueueGrain>(existing.EventId);
            await grain.ReleaseAsync(queueId, completed: body?.Completed ?? false);

            var updated = await index.TryReadAsync(queueId);
            return Results.Ok(updated);
        });

        return app;
    }
}

public sealed record EnqueueRequest(string UserId);

public sealed record ReleaseReservationRequest(bool Completed);
