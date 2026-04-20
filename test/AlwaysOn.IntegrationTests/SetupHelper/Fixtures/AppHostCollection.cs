namespace AlwaysOn.IntegrationTests.SetupHelper.Fixtures;

[CollectionDefinition(Name)]
public sealed class AppHostCollection : ICollectionFixture<AppHostTestFixture>
{
    public const string Name = "AppHost";
}
