using Microsoft.AspNetCore.SignalR;

namespace AlwaysOn.Silo.Hubs;

/// <summary>
/// Self-hosted SignalR hub used to push reservation-ready events to individual
/// users. Clients connect, then invoke <see cref="SubscribeAsync"/> with their
/// anonymous user id so the connection joins the per-user group. Messages pushed
/// to that group arrive via the <c>ReservationReady</c> client method.
/// </summary>
public sealed class QueueHub : Hub
{
    /// <summary>Join the per-user group for <paramref name="userId"/>.</summary>
    public async Task SubscribeAsync(string userId)
    {
        if (string.IsNullOrWhiteSpace(userId))
        {
            throw new HubException("userId is required.");
        }

        await Groups.AddToGroupAsync(Context.ConnectionId, GroupName(userId));
    }

    public static string GroupName(string userId) => $"user:{userId}";
}
