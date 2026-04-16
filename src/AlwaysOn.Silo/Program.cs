using AlwaysOn.Silo.Endpoints;

var builder = WebApplication.CreateBuilder(args);

builder.AddServiceDefaults();

var cosmosConnectionString = builder.Configuration.GetConnectionString("CosmosDb");
if (string.IsNullOrWhiteSpace(cosmosConnectionString))
{
    throw new InvalidOperationException("Missing ConnectionStrings:CosmosDb configuration.");
}

builder.UseOrleans(siloBuilder =>
{
    siloBuilder.UseLocalhostClustering();
    siloBuilder.AddCosmosGrainStorageAsDefault(options =>
    {
        options.ConfigureCosmosClient(cosmosConnectionString);
        options.DatabaseName = builder.Configuration["Orleans:Cosmos:DatabaseName"] ?? "alwayson";
        options.ContainerName = builder.Configuration["Orleans:Cosmos:ContainerName"] ?? "grainState";
        options.IsResourceCreationEnabled = builder.Configuration.GetValue("Orleans:Cosmos:IsResourceCreationEnabled", true);
    });
});

var app = builder.Build();

app.MapDefaultEndpoints();
app.MapEventEndpoints();
app.MapOrderEndpoints();
app.MapTicketEndpoints();

app.Run();
