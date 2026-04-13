using AlwaysOn.Shared.Constants;

var builder = DistributedApplication.CreateBuilder(args);

var cosmos = builder.AddAzureCosmosDB(AspireConstants.CosmosResource);
var db = cosmos.AddCosmosDatabase(AspireConstants.CosmosDb);

var orleans = builder.AddOrleans(AspireConstants.Silo)
                     .WithClustering(db)
                     .WithGrainStorage(db);

var silo = builder.AddProject<Projects.AlwaysOn_Silo>(AspireConstants.Silo)
                  .WithReference(orleans);

builder.AddProject<Projects.AlwaysOn_Gateway>(AspireConstants.Gateway)
    .WithReference(silo)
    .WaitFor(silo);

builder.Build().Run();
