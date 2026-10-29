using Example.Core.Platform;
using Xunit;

namespace Example.Core.Tests;

public sealed class SteamPlatformTests : IDisposable
{
    sealed class FakeSteam : ISteamApi
    {
        public SteamInit InitResult = new(SteamInitOutcome.Ready);
        public Exception? InitThrows;
        public int InitCalls, StoreCalls, CallbackRuns, Shutdowns;
        public bool StoreSucceeds = true, SetAchievementSucceeds = true;
        public readonly HashSet<string> Achievements = new();
        public readonly Dictionary<string, int> Stats = new();
        public readonly List<(string Board, int Score, ScoreMethod Method)> Uploads = new();
        public readonly Dictionary<string, int> Scores = new();
        public readonly Dictionary<string, string> Presence = new();

        public SteamInit Init() { InitCalls++; return InitThrows != null ? throw InitThrows : InitResult; }
        public void RunCallbacks() => CallbackRuns++;
        public bool GetAchievement(string id) => Achievements.Contains(id);
        public bool SetAchievement(string id) { if (SetAchievementSucceeds) Achievements.Add(id); return SetAchievementSucceeds; }
        public bool TryGetStat(string id, out int value) => Stats.TryGetValue(id, out value);
        public bool SetStat(string id, int value) { Stats[id] = value; return true; }
        public bool StoreStats() { StoreCalls++; return StoreSucceeds; }
        public void UploadScore(string leaderboard, int score, ScoreMethod method) => Uploads.Add((leaderboard, score, method));
        public int? GetScore(string leaderboard) => Scores.TryGetValue(leaderboard, out int s) ? s : null;
        public void SetRichPresence(string key, string? value) { if (value == null) Presence.Remove(key); else Presence[key] = value; }
        public void Shutdown() => Shutdowns++;
    }

    readonly string _dir = Directory.CreateTempSubdirectory("breakout-steam-").FullName;
    readonly List<string> _log = new();
    readonly FakeSteam _steam = new();

    public void Dispose() => Directory.Delete(_dir, recursive: true);

    SteamPlatform Platform() => new(_steam, BreakoutProgress.Catalog, _log.Add);
    string LocalPath => Path.Combine(_dir, "platform.json");

    [Fact]
    public void AnAchievementUnlockGoesThroughOnce()
    {
        var platform = Platform();
        Assert.True(platform.UnlockAchievement(BreakoutProgress.FirstFloor));
        Assert.Contains(BreakoutProgress.FirstFloor, _steam.Achievements);
        Assert.False(platform.UnlockAchievement(BreakoutProgress.FirstFloor));
        Assert.True(platform.IsAchievementUnlocked(BreakoutProgress.FirstFloor));
        Assert.False(platform.IsAchievementUnlocked(BreakoutProgress.FifthFloor));
    }

    [Fact]
    public void AnAchievementSteamAlreadyHasIsNotUnlockedAgain()
    {
        _steam.Achievements.Add(BreakoutProgress.Combo10);   // earned on another machine
        var platform = Platform();
        Assert.False(platform.UnlockAchievement(BreakoutProgress.Combo10));
        platform.StoreStats();
        Assert.Equal(0, _steam.StoreCalls);
    }

    [Fact]
    public void ManyChangesAreOneStoreStatsAndNothingChangedIsNone()
    {
        var platform = Platform();
        platform.StoreStats();
        Assert.Equal(0, _steam.StoreCalls);

        for (int i = 1; i <= 50; i++) platform.SetStat(BreakoutProgress.BricksBroken, i);
        platform.UnlockAchievement(BreakoutProgress.FirstFloor);
        Assert.Equal(0, _steam.StoreCalls);   // set calls are held until StoreStats
        platform.StoreStats();
        Assert.Equal(1, _steam.StoreCalls);
        Assert.Equal(50, _steam.Stats[BreakoutProgress.BricksBroken]);
        platform.StoreStats();
        Assert.Equal(1, _steam.StoreCalls);
    }

    [Fact]
    public void AFailedStoreStatsIsLoggedOnceAndTriedAgain()
    {
        var platform = Platform();
        _steam.StoreSucceeds = false;
        platform.SetStat(BreakoutProgress.BricksBroken, 3);
        platform.StoreStats();
        platform.StoreStats();
        Assert.Equal(2, _steam.StoreCalls);
        Assert.Single(_log);
        _steam.StoreSucceeds = true;
        platform.StoreStats();
        Assert.Equal(3, _steam.StoreCalls);
        platform.StoreStats();
        Assert.Equal(3, _steam.StoreCalls);
    }

    [Fact]
    public void ARefusedUnlockIsNotReportedAsUnlocked()
    {
        _steam.SetAchievementSucceeds = false;
        var platform = Platform();
        Assert.False(platform.UnlockAchievement(BreakoutProgress.FirstFloor));
        Assert.False(platform.UnlockAchievement(BreakoutProgress.FirstFloor));
        Assert.False(platform.IsAchievementUnlocked(BreakoutProgress.FirstFloor));
        Assert.Single(_log);   // logged once, not per call
    }

    [Fact]
    public void AMisspeltIdThrowsBeforeReachingSteam()
    {
        var platform = Platform();
        Assert.Throws<ArgumentException>(() => platform.UnlockAchievement("FIRST_FLOR"));
        Assert.Throws<ArgumentException>(() => platform.SetStat("bricks broken", 1));
        Assert.Throws<ArgumentException>(() => platform.SubmitScore("NOPE", 1, ScoreMethod.KeepBest));
        Assert.Empty(_steam.Achievements);
        Assert.Empty(_steam.Stats);
        Assert.Empty(_steam.Uploads);
    }

    [Fact]
    public void KeepBestUploadsOnlyAHigherScore()
    {
        var platform = Platform();
        Assert.True(platform.SubmitScore(BreakoutProgress.HighScore, 500, ScoreMethod.KeepBest));
        Assert.False(platform.SubmitScore(BreakoutProgress.HighScore, 300, ScoreMethod.KeepBest));
        Assert.Equal(500, platform.GetScore(BreakoutProgress.HighScore));
        Assert.True(platform.SubmitScore(BreakoutProgress.HighScore, 300, ScoreMethod.ForceUpdate));
        Assert.Equal(new[] { 500, 300 }, _steam.Uploads.Select(u => u.Score));
        Assert.Equal(ScoreMethod.ForceUpdate, _steam.Uploads[1].Method);
    }

    [Fact]
    public void ASteamScoreFromEarlierPlayCountsAsTheCurrentBest()
    {
        _steam.Scores[BreakoutProgress.HighScore] = 900;
        var platform = Platform();
        Assert.False(platform.SubmitScore(BreakoutProgress.HighScore, 800, ScoreMethod.KeepBest));
        Assert.Empty(_steam.Uploads);
        Assert.Equal(900, platform.GetScore(BreakoutProgress.HighScore));
    }

    [Fact]
    public void RichPresenceKeepsSteamsLimitsAndClearsWithNull()
    {
        var platform = Platform();
        platform.SetRichPresence("steam_display", "#Status_Floor");
        platform.SetRichPresence("floor", "3");
        Assert.Equal("3", _steam.Presence["floor"]);
        Assert.Equal("3", platform.RichPresence["floor"]);
        platform.SetRichPresence("floor", null);
        Assert.DoesNotContain("floor", _steam.Presence.Keys);
        Assert.Throws<ArgumentException>(() => platform.SetRichPresence("steam_display", "Floor"));
        Assert.Throws<ArgumentException>(() => platform.SetRichPresence("k", new string('x', 257)));
        Assert.Equal("#Status_Floor", _steam.Presence["steam_display"]);   // a refused call changed nothing
    }

    [Fact]
    public void BreakoutProgressRunsOnSteamLikeOnTheLocalPlatform()
    {
        var platform = Platform();
        var progress = new BreakoutProgress(platform);
        var run = new RunState();
        progress.RunStarted(run);
        progress.BrickBroken(run);
        progress.FloorCleared(run);
        Assert.Contains(BreakoutProgress.FirstFloor, _steam.Achievements);
        Assert.Equal(1, _steam.Stats[BreakoutProgress.BricksBroken]);
        Assert.Equal(1, _steam.StoreCalls);
        Assert.Equal("#Status_Floor", _steam.Presence["steam_display"]);
    }

    [Fact]
    public void CallbacksRunAndDisposeStoresThenShutsDown()
    {
        var platform = Platform();
        platform.Tick();
        platform.Tick();
        Assert.Equal(2, _steam.CallbackRuns);
        platform.SetStat(BreakoutProgress.BricksBroken, 7);
        platform.Dispose();
        platform.Dispose();
        Assert.Equal(1, _steam.StoreCalls);
        Assert.Equal(1, _steam.Shutdowns);
    }

    [Fact]
    public void WithoutASteamBackendTheLocalPlatformIsUsedAndNothingIsLogged()
    {
        var choice = PlatformFactory.Create(null, LocalPath, BreakoutProgress.Catalog, _log.Add);
        Assert.IsType<LocalPlatform>(choice.Platform);
        Assert.False(choice.UsesSteam);
        Assert.False(choice.QuitRequested);
        Assert.Null(choice.FallbackReason);
        Assert.Empty(_log);
    }

    [Fact]
    public void SteamIsUsedWhenItStarts()
    {
        var choice = PlatformFactory.Create(() => _steam, LocalPath, BreakoutProgress.Catalog, _log.Add);
        Assert.IsType<SteamPlatform>(choice.Platform);
        Assert.True(choice.UsesSteam);
        Assert.Equal(1, _steam.InitCalls);
        Assert.Empty(_log);
    }

    [Fact]
    public void WhenSteamIsNotRunningTheGameFallsBackAndLogsOnce()
    {
        _steam.InitResult = new SteamInit(SteamInitOutcome.Unavailable, "SteamAPI.InitEx returned FailedGeneric: Failed to load module steamclient.so");
        var choice = PlatformFactory.Create(() => _steam, LocalPath, BreakoutProgress.Catalog, _log.Add);
        Assert.IsType<LocalPlatform>(choice.Platform);
        Assert.False(choice.UsesSteam);
        Assert.Contains("steamclient.so", choice.FallbackReason);
        Assert.Single(_log);

        // The fallback still works and keeps progress in the local file.
        Assert.True(choice.Platform.UnlockAchievement(BreakoutProgress.FirstFloor));
        choice.Platform.StoreStats();
        Assert.True(File.Exists(LocalPath));
        Assert.Single(_log);
    }

    [Theory]
    [InlineData(typeof(DllNotFoundException))]
    [InlineData(typeof(BadImageFormatException))]
    [InlineData(typeof(EntryPointNotFoundException))]
    public void AMissingOrWrongNativeLibraryFallsBackInsteadOfCrashing(Type exception)
    {
        _steam.InitThrows = (Exception)Activator.CreateInstance(exception, "libsteam_api.so")!;
        var choice = PlatformFactory.Create(() => _steam, LocalPath, BreakoutProgress.Catalog, _log.Add);
        Assert.IsType<LocalPlatform>(choice.Platform);
        Assert.Contains(exception.Name, choice.FallbackReason);
        Assert.Single(_log);
    }

    [Fact]
    public void AFactoryThatThrowsAlsoFallsBack()
    {
        var choice = PlatformFactory.Create(() => throw new DllNotFoundException("Steamworks.NET"), LocalPath, BreakoutProgress.Catalog, _log.Add);
        Assert.IsType<LocalPlatform>(choice.Platform);
        Assert.Single(_log);
    }

    [Fact]
    public void ARestartRequestIsPassedOnAndSteamIsNotUsed()
    {
        _steam.InitResult = new SteamInit(SteamInitOutcome.RestartRequested);
        var choice = PlatformFactory.Create(() => _steam, LocalPath, BreakoutProgress.Catalog, _log.Add);
        Assert.True(choice.QuitRequested);
        Assert.False(choice.UsesSteam);
    }
}
