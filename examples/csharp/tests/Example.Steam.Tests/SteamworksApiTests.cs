using Example.Core.Platform;
using Example.Steam;
using Xunit;

namespace Example.Steam.Tests;

/// <summary>
/// The real binding, with no Steam client: the library must load (or fail in a way the factory handles) and the
/// game must fall back to the local platform. What needs a client (achievements, leaderboards, overlay) is not run here.
/// </summary>
public sealed class SteamworksApiTests(Xunit.Abstractions.ITestOutputHelper output) : IDisposable
{
    readonly string _dir = Directory.CreateTempSubdirectory("breakout-steam-real-").FullName;
    readonly List<string> _log = new();

    public void Dispose() => Directory.Delete(_dir, recursive: true);

    [Fact]
    public void TheNativeLibraryOfThisPlatformIsNextToTheAssembly()
    {
        string native = OperatingSystem.IsWindows() ? "steam_api64.dll" : OperatingSystem.IsMacOS() ? "libsteam_api.dylib" : "libsteam_api.so";
        Assert.True(Directory.EnumerateFiles(AppContext.BaseDirectory, native, SearchOption.AllDirectories).Any(), $"{native} not found under {AppContext.BaseDirectory}");
    }

    [Fact]
    public void WithoutASteamClientTheFactoryFallsBackToTheLocalPlatform()
    {
        // appId 0 skips RestartAppIfNecessary, which would otherwise try to start Steam.
        var choice = PlatformFactory.Create(() => new SteamworksApi(0), Path.Combine(_dir, "platform.json"), BreakoutProgress.Catalog, _log.Add);
        Assert.False(choice.UsesSteam);
        Assert.False(choice.QuitRequested);
        Assert.IsType<LocalPlatform>(choice.Platform);
        Assert.NotNull(choice.FallbackReason);
        output.WriteLine(choice.FallbackReason);
        Assert.Single(_log);

        Assert.True(choice.Platform.UnlockAchievement(BreakoutProgress.FirstFloor));
        choice.Platform.StoreStats();
    }

    [Fact]
    public void CallsBeforeInitAreHarmless()
    {
        var api = new SteamworksApi(0);
        api.RunCallbacks();
        api.Shutdown();
        Assert.Null(api.GetScore(BreakoutProgress.HighScore));
    }
}
