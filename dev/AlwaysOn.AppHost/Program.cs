using AlwaysOn.Shared.Constants;

var builder = DistributedApplication.CreateBuilder(args);

var k8s = builder.AddKubernetesEnvironment(AspireConstants.KubernetesEnvironment);
var disableOrleansConfig = bool.TryParse(builder.Configuration["Testing:DisableAppHostOrleansConfig"], out var parsedDisable)
    && parsedDisable;

var cosmos = builder
                .AddAzureCosmosDB(AspireConstants.CosmosResource)
                .RunAsEmulator();

var db = cosmos.AddCosmosDatabase(AspireConstants.CosmosDatabase);

if (disableOrleansConfig)
{
    var silo = builder.AddProject<Projects.AlwaysOn_Silo>(AspireConstants.Silo)
           .WithEnvironment("Testing__UseInMemoryOrleans", "true")
           .WithComputeEnvironment(k8s);

    builder.AddViteApp(AspireConstants.WebUI, "../../src/AlwaysOn.WebUI")
           .WithReference(silo)
           .WithHttpEndpoint(port: 5173, env: "PORT")
           .WithComputeEnvironment(k8s);
}
else
{
    var orleans = builder.AddOrleans(AspireConstants.Silo)
                         .WithClustering(db)
                         .WithGrainStorage(db)
                         .WithReminders(db);

    var silo = builder.AddProject<Projects.AlwaysOn_Silo>(AspireConstants.Silo)
           .WithReference(orleans)
           .WithReference(db)
           .WithComputeEnvironment(k8s);

    builder.AddViteApp(AspireConstants.WebUI, "../../src/AlwaysOn.WebUI")
           .WithReference(silo)
           .WithHttpEndpoint(port: 5173, env: "PORT")
           .WithComputeEnvironment(k8s);
}

builder.Build().Run();
