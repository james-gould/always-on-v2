using AlwaysOn.Shared.Constants;

var builder = DistributedApplication.CreateBuilder(args);

var k8s = builder.AddKubernetesEnvironment(AspireConstants.KubernetesEnvironment);
var isTestMode = bool.TryParse(builder.Configuration["Testing:IsTestMode"], out var parsed) && parsed;

var cosmos = builder
                .AddAzureCosmosDB(AspireConstants.CosmosResource)
                .RunAsEmulator();

var db = cosmos.AddCosmosDatabase(AspireConstants.CosmosDatabase);

var silo = builder.AddProject<Projects.AlwaysOn_Silo>(AspireConstants.Silo)
       .WithReference(db)
       .WithComputeEnvironment(k8s);

if (isTestMode)
{
    silo.WithEnvironment("Testing__UseInMemoryOrleans", "true");
}

if (!isTestMode)
{
    builder.AddViteApp(AspireConstants.WebUI, "../../src/AlwaysOn.WebUI")
           .WithReference(silo)
           .WithHttpEndpoint(port: 5173, env: "PORT")
           .WithComputeEnvironment(k8s);
}

builder.Build().Run();
