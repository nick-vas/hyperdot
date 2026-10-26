namespace Cinderloop;

using System;
using System.Globalization;

/// <summary>The game's own flags, after "--" on the command line: --seed=N, --no-save, --track=N, --rivals=N.</summary>
public sealed class LaunchOptions
{
    /// <summary>0: no seed given, so each race is seeded at random.</summary>
    public long RunSeed { get; private set; }
    public bool NoSave { get; private set; }
    public int Track { get; set; } = 1;
    /// <summary>How many rivals race; more than the three in the data repeats them (for stress runs).</summary>
    public int Rivals { get; private set; } = 3;

    public static LaunchOptions Parse(string[] args)
    {
        var options = new LaunchOptions();
        foreach (string arg in args)
        {
            if (arg == "--no-save")
                options.NoSave = true;
            else if (arg.StartsWith("--seed=", StringComparison.Ordinal))
                options.RunSeed = Number(arg, 7);
            else if (arg.StartsWith("--track=", StringComparison.Ordinal))
                options.Track = (int)Math.Max(1, Number(arg, 8));
            else if (arg.StartsWith("--rivals=", StringComparison.Ordinal))
                options.Rivals = (int)Math.Clamp(Number(arg, 9), 0, 31);
        }
        return options;
    }

    public static LaunchOptions FromCommandLine() => Parse(Godot.OS.GetCmdlineUserArgs());

    /// <summary>The number after the flag's "=", 0 when there is none.</summary>
    private static long Number(string arg, int start) =>
        long.TryParse(arg.AsSpan(start), NumberStyles.Integer, CultureInfo.InvariantCulture, out long value) ? value : 0;
}
