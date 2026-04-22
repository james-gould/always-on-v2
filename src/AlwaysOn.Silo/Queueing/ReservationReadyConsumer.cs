using System.Text.Json;
using AlwaysOn.Shared.Constants;
using AlwaysOn.Silo.Hubs;
using Azure.Messaging.ServiceBus;
using Microsoft.AspNetCore.SignalR;

namespace AlwaysOn.Silo.Queueing;

/// <summary>
/// Background consumer of the reservations-ready Service Bus queue. When a
/// <see cref="ReservationReadyMessage"/> arrives, the consumer pushes it to the
/// per-user SignalR group so the client's WebSocket promotes immediately,
/// rather than waiting for the next /myqueue poll.
/// </summary>
internal sealed class ReservationReadyConsumer(
    ServiceBusClient client,
    IHubContext<QueueHub> hubContext,
    ILogger<ReservationReadyConsumer> logger) : BackgroundService
{
    private static readonly JsonSerializerOptions _jsonOptions = new(JsonSerializerDefaults.Web);

    private ServiceBusProcessor? _processor;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _processor = client.CreateProcessor(AspireConstants.ReservationsQueue, new ServiceBusProcessorOptions
        {
            AutoCompleteMessages = false,
            MaxConcurrentCalls = 8,
        });

        _processor.ProcessMessageAsync += HandleMessageAsync;
        _processor.ProcessErrorAsync += HandleErrorAsync;

        try
        {
            await _processor.StartProcessingAsync(stoppingToken);
            await Task.Delay(Timeout.Infinite, stoppingToken);
        }
        catch (OperationCanceledException)
        {
            // Normal shutdown.
        }
        finally
        {
            if (_processor is not null)
            {
                await _processor.StopProcessingAsync(CancellationToken.None);
                await _processor.DisposeAsync();
                _processor = null;
            }
        }
    }

    private async Task HandleMessageAsync(ProcessMessageEventArgs args)
    {
        try
        {
            var message = JsonSerializer.Deserialize<ReservationReadyMessage>(
                args.Message.Body.ToString(),
                _jsonOptions);

            if (message is null)
            {
                logger.LogWarning("Received empty reservation-ready message; dead-lettering.");
                await args.DeadLetterMessageAsync(args.Message, "EmptyPayload", "Deserialization returned null.");
                return;
            }

            await hubContext.Clients
                .Group(QueueHub.GroupName(message.UserId))
                .SendAsync("ReservationReady", message, args.CancellationToken);

            await args.CompleteMessageAsync(args.Message);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to process reservation-ready message {MessageId}.", args.Message.MessageId);
            await args.AbandonMessageAsync(args.Message);
        }
    }

    private Task HandleErrorAsync(ProcessErrorEventArgs args)
    {
        logger.LogError(
            args.Exception,
            "Service Bus processor error for {Entity} ({Source}).",
            args.EntityPath,
            args.ErrorSource);
        return Task.CompletedTask;
    }
}
