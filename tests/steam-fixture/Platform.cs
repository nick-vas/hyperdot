// Steamworks.NET calls for tests/Test-Steam.ps1; every name here is right. Some are passed as constants, two to a line;
// Shared has another value in progress.gd, so which one is meant is not known and it is not followed.
using Steamworks;

public static class Platform
{
    public const string Combo = "ACH_COMBO_10", Menu = "#Status_Menu";
    public static readonly string Shared = "ACH_SHARED_CS";

    public static void OnCombo()
    {
        SteamUserStats.SetAchievement(Combo);
        SteamUserStats.SetAchievement(Platform.Shared);
        SteamUserStats.GetStat("bricks_broken", out int _);
        SteamFriends.SetRichPresence("steam_display", Menu);
        SteamUserStats.StoreStats();
    }
}
