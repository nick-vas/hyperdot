using Example.Core.Platform;
using Steamworks;

namespace Example.Steam;

/// <summary>
/// <see cref="ISteamApi"/> over Steamworks.NET: one call of the real API for each method. It needs the Steam client and
/// <c>libsteam_api</c> (<c>steam_api64.dll</c>) next to the game; without them <see cref="Init"/> returns
/// Unavailable, or throws DllNotFoundException, which <see cref="PlatformFactory"/> turns into the local platform.
/// Set <c>SteamAppId</c> with Godot's <c>OS.SetEnvironment</c> before <see cref="Init"/> (not with .NET's
/// Environment.SetEnvironmentVariable, which the native API never sees on Linux), or keep a steam_appid.txt next to the
/// executable in testing and out of the shipped depot.
/// </summary>
public sealed class SteamworksApi : ISteamApi
{
    readonly uint _appId;
    readonly Dictionary<string, Board> _boards = new();
    bool _initialised;

    sealed class Board
    {
        public SteamLeaderboard_t? Handle;
        public bool Finding;
        public int? Score;
        public readonly List<(int Score, ScoreMethod Method)> Pending = new();
        public CallResult<LeaderboardFindResult_t>? Find;
        public CallResult<LeaderboardScoreUploaded_t>? Upload;
    }

    /// <param name="appId">Your App ID; 480 (Spacewar) for a test without one. 0 skips the relaunch check.</param>
    public SteamworksApi(uint appId) => _appId = appId;

    public SteamInit Init()
    {
        if (_appId != 0 && SteamAPI.RestartAppIfNecessary(new AppId_t(_appId))) return new SteamInit(SteamInitOutcome.RestartRequested);
        var result = SteamAPI.InitEx(out string message);
        if (result != ESteamAPIInitResult.k_ESteamAPIInitResult_OK)
            return new SteamInit(SteamInitOutcome.Unavailable, $"SteamAPI.InitEx returned {result}: {message}");
        _initialised = true;
        return new SteamInit(SteamInitOutcome.Ready);
    }

    public void RunCallbacks() { if (_initialised) SteamAPI.RunCallbacks(); }

    public bool GetAchievement(string id) => SteamUserStats.GetAchievement(id, out bool achieved) && achieved;
    public bool SetAchievement(string id) => SteamUserStats.SetAchievement(id);
    public bool TryGetStat(string id, out int value) => SteamUserStats.GetStat(id, out value);
    public bool SetStat(string id, int value) => SteamUserStats.SetStat(id, value);
    public bool StoreStats() => SteamUserStats.StoreStats();

    public void SetRichPresence(string key, string? value) => SteamFriends.SetRichPresence(key, value);

    public int? GetScore(string leaderboard) => _boards.TryGetValue(leaderboard, out var board) ? board.Score : null;

    public void UploadScore(string leaderboard, int score, ScoreMethod method)
    {
        if (!_boards.TryGetValue(leaderboard, out var board)) _boards[leaderboard] = board = new Board();
        if (board.Handle is SteamLeaderboard_t handle) { Send(board, handle, score, method); return; }
        board.Pending.Add((score, method));
        if (board.Finding) return;
        board.Finding = true;
        board.Find = CallResult<LeaderboardFindResult_t>.Create((found, failed) =>
        {
            board.Finding = false;
            if (failed || found.m_bLeaderboardFound == 0) { board.Pending.Clear(); return; }
            board.Handle = found.m_hSteamLeaderboard;
            foreach (var (pendingScore, pendingMethod) in board.Pending) Send(board, found.m_hSteamLeaderboard, pendingScore, pendingMethod);
            board.Pending.Clear();
        });
        // The board's sort order is fixed where it is created in Steamworks; this only names it if it is missing.
        board.Find.Set(SteamUserStats.FindOrCreateLeaderboard(leaderboard, ELeaderboardSortMethod.k_ELeaderboardSortMethodDescending,
            ELeaderboardDisplayType.k_ELeaderboardDisplayTypeNumeric));
    }

    static void Send(Board board, SteamLeaderboard_t handle, int score, ScoreMethod method)
    {
        board.Upload = CallResult<LeaderboardScoreUploaded_t>.Create((uploaded, failed) =>
        {
            // m_nScore is the score sent; Steam keeps it only when m_bScoreChanged (KeepBest may keep the old one).
            if (!failed && uploaded.m_bSuccess != 0 && uploaded.m_bScoreChanged != 0) board.Score = uploaded.m_nScore;
        });
        var how = method == ScoreMethod.KeepBest
            ? ELeaderboardUploadScoreMethod.k_ELeaderboardUploadScoreMethodKeepBest
            : ELeaderboardUploadScoreMethod.k_ELeaderboardUploadScoreMethodForceUpdate;
        board.Upload.Set(SteamUserStats.UploadLeaderboardScore(handle, how, score, null, 0));
    }

    public void Shutdown()
    {
        if (!_initialised) return;
        _initialised = false;
        SteamAPI.Shutdown();
    }
}
