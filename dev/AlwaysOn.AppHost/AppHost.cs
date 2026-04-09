var builder = DistributedApplication.CreateBuilder(args);

var silo = builder.AddProject<Projects.AlwaysOn_Silo>("silo");

builder.AddProject<Projects.AlwaysOn_Gateway>("gateway")
    .WithReference(silo)
    .WaitFor(silo);

builder.Build().Run();
