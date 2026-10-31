using System;
using Example.Core.Platform;
using Godot;

namespace Example;

/// <summary>
/// Chooses the platform backend once, at start-up. The default is <see cref="LocalPlatform"/>. A build made with
/// <c>-p:Steam=true</c> defines STEAM, references Example.Steam (Steamworks.NET.AnyCPU) and tries Steam first; when
/// Steam is not running, or its native library is missing, it logs one line and uses the local platform.
/// </summary>
public static class GamePlatform
{
    /// <summary>Valve's public test app (Spacewar). Replace with your App ID when you have one.</summary>
    public const uint AppId = 480;

    public static PlatformChoice Start()
    {
        Func<ISteamApi>? steam = null;
#if STEAM
        steam = () =>
        {
            // In the editor and debug builds there is no Steam launcher to set the App ID; Godot's OS.SetEnvironment
            // reaches the native API, .NET's Environment.SetEnvironmentVariable does not (steam).
            if (OS.IsDebugBuild() && !OS.HasEnvironment("SteamAppId")) OS.SetEnvironment("SteamAppId", AppId.ToString());
            return new Example.Steam.SteamworksApi(AppId);
        };
#endif
        string local = ProjectSettings.GlobalizePath("user://platform.json");
        return PlatformFactory.Create(steam, local, BreakoutProgress.Catalog, GD.Print);
    }
}
