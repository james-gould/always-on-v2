using AlwaysOn.Shared.Constants;

var builder = DistributedApplication.CreateBuilder(args);

var k8s = builder.AddKubernetesEnvironment(AspireConstants.KubernetesEnvironment);
var isTestMode = bool.TryParse(builder.Configuration["Testing:IsTestMode"], out var parsed) && parsed;

var cosmos = builder
                .AddAzureCosmosDB(AspireConstants.CosmosResource)
                .RunAsEmulator();

var db = cosmos.AddCosmosDatabase(AspireConstants.CosmosDatabase);

var cache = builder
                .AddRedis(AspireConstants.RedisCache);

var eventGrid = builder.AddConnectionString(AspireConstants.EventGrid);

var silo = builder.AddProject<Projects.AlwaysOn_Silo>(AspireConstants.Silo)
       .WithReference(db)
       .WithReference(cache)
       .WithReference(eventGrid)
       .WaitFor(cache)
       .WithComputeEnvironment(k8s);

if (isTestMode)
{
    silo.WithEnvironment("Testing__UseInMemoryOrleans", "true");
}

if (!isTestMode)
{
    builder.AddViteApp(AspireConstants.WebUI, "../../src/AlwaysOn.WebUI")
           .WithReference(silo)
           .WithHttpEndpoint(port: 5173, name: "vite", env: "PORT")
           .WithComputeEnvironment(k8s);
}

builder.Build().Run();
