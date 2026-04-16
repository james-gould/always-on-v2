using AlwaysOn.Shared.Constants;

var builder = DistributedApplication.CreateBuilder(args);

builder.AddAzureContainerAppEnvironment(AspireConstants.ContainerAppsEnvironment)
       .WithAzdResourceNaming();

var cosmos = builder
                .AddAzureCosmosDB(AspireConstants.CosmosResource)
                .RunAsEmulator();

var db = cosmos.AddCosmosDatabase(AspireConstants.CosmosDatabase);

var orleans = builder.AddOrleans(AspireConstants.Silo)
                     .WithClustering(db)
            .WithGrainStorage(db)
            .WithReminders(db);

var silo = builder.AddProject<Projects.AlwaysOn_Silo>(AspireConstants.Silo)
            .WithReference(orleans)
            .WithReference(db)
            .WithExternalHttpEndpoints();

builder.Build().Run();
