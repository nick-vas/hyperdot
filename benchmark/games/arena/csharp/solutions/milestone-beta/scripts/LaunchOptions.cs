namespace Glimmerpit;

using System;
using System.Globalization;

/// <summary>
/// The game's own flags, after "--" on the command line: --autoplay, --seed=N, --no-save, --lag=MS, --server, --port=N,
/// and the soak contract's --soak-role=server|client, --soak-port=N and --soak-id=N.
/// </summary>
public sealed class LaunchOptions
{
    public const int DefaultPort = 24650;

    public bool Autoplay { get; private set; }
    /// <summary>0: no seed given, so the bots and the jitter are seeded at random.</summary>
    public long RunSeed { get; private set; }
    public bool NoSave { get; private set; }
    /// <summary>A simulated round trip for local play, in milliseconds (half each way).</summary>
    public int LagMs { get; private set; }
    /// <summary>A dedicated server, headless, with no local player.</summary>
    public bool Server { get; private set; }
    public int Port { get; private set; } = DefaultPort;
    public string SoakRole { get; private set; } = "";
    public int SoakId { get; private set; }

    public static LaunchOptions Parse(string[] args)
    {
        var options = new LaunchOptions();
        foreach (string arg in args)
        {
            int eq = arg.IndexOf('=', StringComparison.Ordinal);
            string name = eq < 0 ? arg : arg[..eq];
            string value = eq < 0 ? "" : arg[(eq + 1)..];
            switch (name)
            {
                case "--autoplay":
                    options.Autoplay = true;
                    break;
                case "--no-save":
                    options.NoSave = true;
                    break;
                case "--server":
                    options.Server = true;
                    break;
                case "--seed":
                    options.RunSeed = Number(value);
                    break;
                case "--lag":
                    options.LagMs = (int)Math.Clamp(Number(value), 0, 1000);
                    break;
                case "--port":
                case "--soak-port":
                    options.Port = (int)Number(value);
                    break;
                case "--soak-role":
                    options.SoakRole = value;
                    break;
                case "--soak-id":
                    options.SoakId = (int)Number(value);
                    break;
            }
        }
        if (options.SoakRole == "server")
            options.Server = true;
        return options;
    }

    public static LaunchOptions FromCommandLine() => Parse(Godot.OS.GetCmdlineUserArgs());

    /// <summary>The seed of the n-th match of a run with --seed, so a run replays; 0 without it (the game picks one at random).</summary>
    public long MatchSeed(int n) => RunSeed > 0 ? RunSeed * 1009 + n : 0;

    private static long Number(string value) =>
        long.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out long number) ? number : 0;
}
