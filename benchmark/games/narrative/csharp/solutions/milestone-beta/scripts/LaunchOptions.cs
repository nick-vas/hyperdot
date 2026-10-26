namespace SaltmereCrossing;

/// <summary>The game's own flags, after "--" on the command line: --autoplay, --no-save.</summary>
public sealed class LaunchOptions
{
    /// <summary>The bot plays the story through to every ending, one after another, then quits.</summary>
    public bool Autoplay { get; private set; }
    public bool NoSave { get; private set; }

    public static LaunchOptions Parse(string[] args)
    {
        var options = new LaunchOptions();
        foreach (string arg in args)
        {
            if (arg == "--autoplay")
                options.Autoplay = true;
            else if (arg == "--no-save")
                options.NoSave = true;
        }
        return options;
    }

    public static LaunchOptions FromCommandLine() => Parse(Godot.OS.GetCmdlineUserArgs());
}
