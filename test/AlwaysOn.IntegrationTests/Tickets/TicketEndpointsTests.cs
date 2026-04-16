using System.Net.Http.Json;
using AlwaysOn.IntegrationTests.SetupHelper.Fixtures;
using AlwaysOn.IntegrationTests.SetupHelper.Models;

namespace AlwaysOn.IntegrationTests.Tickets;

public sealed class TicketEndpointsTests(TicketsTestingFixture fixture) : IClassFixture<TicketsTestingFixture>
{
    [Fact]
    public async Task PostTicketThenGetTicketReturnsIssuedTicket()
    {
        var client = await fixture.GetClientAsync();

        var ticketId = Guid.NewGuid().ToString("N");

        var request = new IssueTicketRequest(
            TicketId: ticketId,
            EventId: Guid.NewGuid().ToString("N"),
            OrderId: Guid.NewGuid().ToString("N"),
            UserId: Guid.NewGuid().ToString("N"));

        var postResponse = await client.PostAsJsonAsync("/tickets", request);

        postResponse.EnsureSuccessStatusCode();

        var getResponse = await client.GetAsync($"/tickets/{ticketId}");

        getResponse.EnsureSuccessStatusCode();

        var body = await getResponse.Content.ReadAsStringAsync();

        Assert.Contains(ticketId, body, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("issued", body, StringComparison.OrdinalIgnoreCase);
    }
}
