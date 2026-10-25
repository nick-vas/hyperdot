namespace Bramblegate;

using System;
using System.Globalization;

/// <summary>The game's own flags, after "--" on the command line: --autoplay, --seed=N, --no-save, --map=N, --speed=N.</summary>
public sealed class LaunchOptions
{
    public bool Autoplay { get; private set; }
    /// <summary>0: no seed given, so each battle draws its own.</summary>
    public long RunSeed { get; private set; }
    public bool NoSave { get; private set; }
    public int Map { get; private set; } = 1;
    /// <summary>Battle ticks per physics tick: 1 is normal speed; a bot run defaults to 3.</summary>
    public int Speed { get; private set; } = 1;

    public static LaunchOptions Parse(string[] args)
    {
        var options = new LaunchOptions();
        bool speedGiven = false;
        foreach (string arg in args)
        {
            if (arg == "--autoplay")
            {
                options.Autoplay = true;
            }
            else if (arg == "--no-save")
            {
                options.NoSave = true;
            }
            else if (arg.StartsWith("--seed=", StringComparison.Ordinal))
            {
                options.RunSeed = Number(arg, 7);
            }
            else if (arg.StartsWith("--map=", StringComparison.Ordinal))
            {
                options.Map = (int)Math.Max(1, Number(arg, 6));
            }
            else if (arg.StartsWith("--speed=", StringComparison.Ordinal))
            {
                options.Speed = (int)Math.Clamp(Number(arg, 8), 1, 8);
                speedGiven = true;
            }
        }
        if (options.Autoplay && !speedGiven)
            options.Speed = 3;
        return options;
    }

    /// <summary>The number after the flag's "="; 0 when there is none, as GDScript's int() gives.</summary>
    private static long Number(string arg, int start) =>
        long.TryParse(arg.AsSpan(start), NumberStyles.Integer, CultureInfo.InvariantCulture, out long value) ? value : 0;

    public static LaunchOptions FromCommandLine() => Parse(Godot.OS.GetCmdlineUserArgs());
}
