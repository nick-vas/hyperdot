namespace Lanternfen;

using System;
using System.Globalization;

/// <summary>The game's own flags, after "--" on the command line: --autoplay, --seed=N, --no-save, --rival=N.</summary>
public sealed class LaunchOptions
{
    public bool Autoplay { get; private set; }
    /// <summary>0: no seed given, so each duel is shuffled at random.</summary>
    public long RunSeed { get; private set; }
    public bool NoSave { get; private set; }
    public int Rival { get; private set; } = 1;

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
                options.RunSeed = long.TryParse(arg.AsSpan(7), NumberStyles.Integer, CultureInfo.InvariantCulture, out long seed) ? seed : 0;
            else if (arg.StartsWith("--rival=", StringComparison.Ordinal))
                options.Rival = Math.Max(1, int.TryParse(arg.AsSpan(8), NumberStyles.Integer, CultureInfo.InvariantCulture, out int rival) ? rival : 0);
        }
        return options;
    }

    public static LaunchOptions FromCommandLine() => Parse(Godot.OS.GetCmdlineUserArgs());
}
