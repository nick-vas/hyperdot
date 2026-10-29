namespace Example.Core.Platform;

/// <summary>How <see cref="ISteamApi.Init"/> went.</summary>
public enum SteamInitOutcome
{
    Ready,
    /// <summary>Steam asked for the game to be started through the client; the process should quit at once.</summary>
    RestartRequested,
    /// <summary>No client running, the native library missing, or the init failed: play without Steam.</summary>
    Unavailable,
}

public readonly record struct SteamInit(SteamInitOutcome Outcome, string? Message = null);

/// <summary>
/// The few Steamworks calls <see cref="SteamPlatform"/> makes, one to one with the real API (SteamUserStats, SteamFriends,
/// SteamAPI) so that the backend can be tested with a fake. The real one is <c>Example.Steam.SteamworksApi</c>, in a project the
/// game references only when it is built with <c>-p:Steam=true</c>.
/// </summary>
public interface ISteamApi
{
    SteamInit Init();
    /// <summary>Once per frame: Steam's callbacks (a leaderboard answer) run here, on the caller's thread.</summary>
    void RunCallbacks();
    bool GetAchievement(string id);
    /// <summary>False when Steam refused (not connected, unknown name).</summary>
    bool SetAchievement(string id);
    bool TryGetStat(string id, out int value);
    bool SetStat(string id, int value);
    /// <summary>One round trip to Steam; false when it could not be sent.</summary>
    bool StoreStats();
    /// <summary>Asks for the upload; Steam answers later, through <see cref="RunCallbacks"/>.</summary>
    void UploadScore(string leaderboard, int score, ScoreMethod method);
    /// <summary>The player's score as Steam last reported it; null when not known yet.</summary>
    int? GetScore(string leaderboard);
    void SetRichPresence(string key, string? value);
    void Shutdown();
}

/// <summary>
/// <see cref="IPlatformServices"/> on Steam, through <see cref="ISteamApi"/>. Ids are checked against the catalog as in
/// <see cref="LocalPlatform"/>. Stat and achievement changes go to Steam at once (cheap) and are sent by
/// <see cref="StoreStats"/> only when something changed since the last one: Steam rate limits StoreStats to about one
/// call a few minutes. A Steam call that fails is logged once per kind and never throws.
/// </summary>
public sealed class SteamPlatform : IPlatformServices, IDisposable
{
    readonly ISteamApi _api;
    readonly PlatformCatalog _catalog;
    readonly Action<string> _log;
    readonly Dictionary<string, string> _presence = new();
    readonly Dictionary<string, int> _scores = new();
    readonly HashSet<string> _unlocked = new();
    readonly HashSet<string> _logged = new();
    bool _dirty, _disposed;

    /// <summary>Call after <see cref="ISteamApi.Init"/> returned Ready.</summary>
    public SteamPlatform(ISteamApi api, PlatformCatalog catalog, Action<string> log)
    {
        _api = api;
        _catalog = catalog;
        _log = log;
    }

    public void Tick() => _api.RunCallbacks();

    public bool UnlockAchievement(string id)
    {
        Known(_catalog.Achievements, id, "achievement");
        if (_unlocked.Contains(id)) return false;
        if (_api.GetAchievement(id)) { _unlocked.Add(id); return false; }
        if (!_api.SetAchievement(id)) { LogOnce($"SetAchievement({id}) failed; the achievement is not unlocked on Steam"); return false; }
        _unlocked.Add(id);
        _dirty = true;
        return true;
    }

    public bool IsAchievementUnlocked(string id)
    {
        Known(_catalog.Achievements, id, "achievement");
        return _unlocked.Contains(id) || (_api.GetAchievement(id) && _unlocked.Add(id));
    }

    public int GetStat(string id)
    {
        Known(_catalog.Stats, id, "stat");
        if (_api.TryGetStat(id, out int value)) return value;
        LogOnce($"GetStat({id}) failed; reading 0");
        return 0;
    }

    public void SetStat(string id, int value)
    {
        Known(_catalog.Stats, id, "stat");
        if (_api.SetStat(id, value)) _dirty = true;
        else LogOnce($"SetStat({id}) failed; the value is not kept");
    }

    public bool SubmitScore(string leaderboard, int score, ScoreMethod method)
    {
        Known(_catalog.Leaderboards, leaderboard, "leaderboard");
        int? current = GetScore(leaderboard);
        if (method == ScoreMethod.KeepBest && current is int best && best >= score) return false;
        if (current == score) return false;
        _api.UploadScore(leaderboard, score, method);
        _scores[leaderboard] = score;
        return true;
    }

    public int? GetScore(string leaderboard)
    {
        Known(_catalog.Leaderboards, leaderboard, "leaderboard");
        return _api.GetScore(leaderboard) ?? (_scores.TryGetValue(leaderboard, out int score) ? score : null);
    }

    public IReadOnlyDictionary<string, string> RichPresence => _presence;

    public void SetRichPresence(string key, string? value)
    {
        LocalPlatform.CheckRichPresence(_presence, key, value);
        _api.SetRichPresence(key, value);
        if (value == null) _presence.Remove(key); else _presence[key] = value;
    }

    public void StoreStats()
    {
        if (!_dirty) return;
        if (_api.StoreStats()) _dirty = false;
        else LogOnce("StoreStats could not be sent; it is tried again at the next StoreStats");
    }

    /// <summary>Stores what is pending and shuts Steam down.</summary>
    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        StoreStats();
        _api.Shutdown();
    }

    void LogOnce(string message)
    {
        if (_logged.Add(message)) _log("Steam: " + message);
    }

    static void Known(IReadOnlySet<string> ids, string id, string kind)
    {
        if (!ids.Contains(id)) throw new ArgumentException($"unknown {kind} '{id}' (not in the platform catalog)");
    }
}

/// <summary>What <see cref="PlatformFactory.Create"/> chose.</summary>
/// <param name="Platform">Steam, or <see cref="LocalPlatform"/> when Steam is not built in or not available.</param>
/// <param name="QuitRequested">Steam wants the game started through the client: quit now, before showing anything.</param>
/// <param name="FallbackReason">Why Steam was not used; null when it is, or when no Steam backend was asked for.</param>
public sealed record PlatformChoice(IPlatformServices Platform, bool UsesSteam, bool QuitRequested, string? FallbackReason);

public static class PlatformFactory
{
    /// <summary>
    /// Steam when <paramref name="createSteam"/> is given and Steam starts; otherwise the local platform, the default.
    /// A build without the Steam project passes null. A missing native library, a failed init or a thrown exception
    /// logs one line and falls back, so a game outside Steam (itch.io, tests, CI) runs unchanged.
    /// </summary>
    public static PlatformChoice Create(Func<ISteamApi>? createSteam, string localPath, PlatformCatalog catalog, Action<string> log)
    {
        string reason;
        if (createSteam == null) return new PlatformChoice(new LocalPlatform(localPath, catalog), false, false, null);
        try
        {
            var api = createSteam();
            var init = api.Init();
            switch (init.Outcome)
            {
                case SteamInitOutcome.Ready:
                    return new PlatformChoice(new SteamPlatform(api, catalog, log), true, false, null);
                case SteamInitOutcome.RestartRequested:
                    return new PlatformChoice(new LocalPlatform(localPath, catalog), false, true, "Steam asked for a restart through the client");
                default:
                    reason = init.Message ?? "Steam is not available";
                    break;
            }
        }
        catch (Exception e) when (e is DllNotFoundException or BadImageFormatException or EntryPointNotFoundException or InvalidOperationException)
        {
            reason = $"{e.GetType().Name}: {e.Message}";
        }
        log($"Steam not used ({reason}); playing with the local platform.");
        return new PlatformChoice(new LocalPlatform(localPath, catalog), false, false, reason);
    }
}
