using System.Text.Json;
using AlwaysOn.Silo.Hubs;
using Azure.Messaging.EventGrid.Namespaces;
using Microsoft.AspNetCore.SignalR;

namespace AlwaysOn.Silo.Queueing;

/// <summary>
/// Background consumer that pulls events from the Event Grid namespace topic
/// subscription using pull delivery. When a <see cref="ReservationReadyMessage"/>
/// arrives, the consumer pushes it to the per-user SignalR group so the client's
/// WebSocket promotes immediately, rather than waiting for the next /myqueue poll.
/// </summary>
internal sealed class ReservationReadyConsumer(
    EventGridReceiverClient receiverClient,
    IHubContext<QueueHub> hubContext,
    ILogger<ReservationReadyConsumer> logger) : BackgroundService
{
    private static readonly JsonSerializerOptions _jsonOptions = new(JsonSerializerDefaults.Web);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                ReceiveResult result = await receiverClient.ReceiveAsync(
                    maxEvents: 10,
                    maxWaitTime: TimeSpan.FromSeconds(30),
                    stoppingToken);

                foreach (var detail in result.Details)
                {
                    await ProcessEventAsync(detail, stoppingToken);
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Error receiving events from Event Grid.");
                await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
            }
        }
    }

    private async Task ProcessEventAsync(ReceiveDetails detail, CancellationToken ct)
    {
        var lockToken = detail.BrokerProperties.LockToken;

        try
        {
            var message = detail.Event.Data?.ToObjectFromJson<ReservationReadyMessage>(_jsonOptions);

            if (message is null)
            {
                logger.LogWarning("Received empty reservation-ready event; rejecting.");
                await receiverClient.RejectAsync([lockToken], ct);
                return;
            }

            await hubContext.Clients
                .Group(QueueHub.GroupName(message.UserId))
                .SendAsync("ReservationReady", message, ct);

            await receiverClient.AcknowledgeAsync([lockToken], ct);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to process reservation-ready event; releasing for redelivery.");
            await receiverClient.ReleaseAsync([lockToken], null, ct);
        }
    }
}
