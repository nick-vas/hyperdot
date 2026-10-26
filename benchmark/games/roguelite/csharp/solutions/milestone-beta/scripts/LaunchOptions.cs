namespace Wickerdeep;

using System;
using System.Globalization;

/// <summary>The game's own flags, after "--" on the command line: --autoplay, --seed=N, --no-save, --floor=N, --swarm=N.</summary>
public sealed class LaunchOptions
{
    public bool Autoplay { get; private set; }
    /// <summary>0: no seed given, so each run is seeded at random.</summary>
    public long RunSeed { get; private set; }
    public bool NoSave { get; private set; }
    /// <summary>The floor a run starts on.</summary>
    public int FloorNumber { get; private set; } = 1;
    /// <summary>Extra bats hunting the wick on every floor: the load for bench.</summary>
    public int Swarm { get; private set; }

    public static LaunchOptions Parse(string[] args)
    {
        var options = new LaunchOptions();
        foreach (string arg in args)
        {
            if (arg == "--autoplay")
                options.Autoplay = true;
            else if (arg == "--no-save")
                options.NoSave = true;
            else if (arg.StartsWith("--seed=", StringComparison.Ordinal))
                options.RunSeed = Number(arg, 7);
            else if (arg.StartsWith("--floor=", StringComparison.Ordinal))
                options.FloorNumber = (int)Math.Max(1, Number(arg, 8));
            else if (arg.StartsWith("--swarm=", StringComparison.Ordinal))
                options.Swarm = (int)Math.Max(0, Number(arg, 8));
        }
        return options;
    }

    public static LaunchOptions FromCommandLine() => Parse(Godot.OS.GetCmdlineUserArgs());

    /// <summary>The number after the flag's "=", 0 when there is none.</summary>
    private static long Number(string arg, int start) =>
        long.TryParse(arg.AsSpan(start), NumberStyles.Integer, CultureInfo.InvariantCulture, out long value) ? value : 0;
}
