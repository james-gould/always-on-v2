using Aspire.Hosting.ApplicationModel;
using Aspire.Hosting;
using Aspire.Hosting.Testing;
using Microsoft.Extensions.DependencyInjection;

namespace AlwaysOn.IntegrationTests.SetupHelper.Fixtures;

public sealed class AppHostTestFixture : IAsyncLifetime
{
    private readonly TimeSpan _waitTimeout = TimeSpan.FromSeconds(45);

    private DistributedApplication? _app;
    private ResourceNotificationService? _notifications;
    private HttpClient? _client;

    private string SiloResourceName => "silo";

    public string NewId() => Guid.NewGuid().ToString("N");

    public async Task InitializeAsync()
    {
        var builder = await DistributedApplicationTestingBuilder
            .CreateAsync<Projects.AlwaysOn_AppHost>(
            ["--Testing:IsTestMode=true"],
            (options, _) =>
            {
                options.DisableDashboard = true;
            });

        _app = await builder.BuildAsync();
        _notifications = _app.Services.GetService<ResourceNotificationService>();

        await _app.StartAsync();

        if (_notifications is not null)
            await _notifications.WaitForResourceHealthyAsync(SiloResourceName).WaitAsync(_waitTimeout);

        _client = _app.CreateHttpClient(SiloResourceName);
    }

    public ValueTask<HttpClient> GetClientAsync()
    {
        if (_client is null)
        {
            throw new InvalidOperationException("The test fixture has not been initialized.");
        }

        return ValueTask.FromResult(_client);
    }

    public async Task DisposeAsync()
    {
        _client?.Dispose();

        if (_app is not null)
        {
            await _app.DisposeAsync();
        }
    }
}
