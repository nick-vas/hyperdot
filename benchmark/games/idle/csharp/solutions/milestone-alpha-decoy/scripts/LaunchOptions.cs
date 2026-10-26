namespace Duskhive;

using System;
using System.Globalization;

/// <summary>The game's own flags, after "--" on the command line: --no-save, --speed=N.</summary>
public sealed class LaunchOptions
{
    public bool NoSave { get; private set; }

    /// <summary>Seconds of play per second of game time (1 to 600).</summary>
    public double Speed { get; private set; } = 1.0;

    public static LaunchOptions Parse(string[] args)
    {
        var options = new LaunchOptions();
        foreach (string arg in args)
        {
            if (arg == "--no-save")
                options.NoSave = true;
            else if (arg.StartsWith("--speed=", StringComparison.Ordinal))
                options.Speed = Math.Clamp(Number(arg.Substring("--speed=".Length)), 1.0, 600.0);
        }
        return options;
    }

    public static LaunchOptions FromCommandLine() => Parse(Godot.OS.GetCmdlineUserArgs());

    /// <summary>The number in a flag, 0 when it is not one (as float() of text gives).</summary>
    private static double Number(string text) =>
        double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out double value) ? value : 0.0;
}
