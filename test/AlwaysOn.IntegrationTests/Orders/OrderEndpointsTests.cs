using System.Net.Http.Json;
using AlwaysOn.IntegrationTests.SetupHelper.Fixtures;
using AlwaysOn.IntegrationTests.SetupHelper.Models;

namespace AlwaysOn.IntegrationTests.Orders;

public sealed class OrderEndpointsTests(OrdersTestingFixture fixture) : IClassFixture<OrdersTestingFixture>
{
    [Fact]
    public async Task PostOrderWithQuantityCreatesOrderAndTicketIds()
    {
        var client = await fixture.GetClientAsync();

        var request = new CreateOrderRequest(
            OrderId: Guid.NewGuid().ToString("N"),
            EventId: Guid.NewGuid().ToString("N"),
            UserId: Guid.NewGuid().ToString("N"),
            TicketQuantity: 2);

        var response = await client.PostAsJsonAsync("/orders", request);

        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadAsStringAsync();

        Assert.Contains("ticketIds", body, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("tickets", body, StringComparison.OrdinalIgnoreCase);
    }
}
