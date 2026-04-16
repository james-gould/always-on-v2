using AlwaysOn.Shared.Constants;

var builder = DistributedApplication.CreateBuilder(args);

var k8s = builder.AddKubernetesEnvironment(AspireConstants.KubernetesEnvironment);

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
            .WithComputeEnvironment(k8s);

builder.Build().Run();
