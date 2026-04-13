var builder = WebApplication.CreateBuilder(args);

builder.AddServiceDefaults();

builder.UseOrleans(siloBuilder =>
{
    siloBuilder.UseLocalhostClustering();
    siloBuilder.AddMemoryGrainStorageAsDefault();

    siloBuilder.AddCosmosGrainStorage(
                name: "cosmosStore",
                configureOptions: options =>
                {
                    options.AccountEndpoint = "https://YOUR_COSMOS_ENDPOINT";
                    options.AccountKey = "YOUR_COSMOS_KEY";
                    options.DB = "YOUR_DATABASE_NAME";
                    options.CanCreateResources = true;
                });
});

var app = builder.Build();

app.MapDefaultEndpoints();

app.Run();
