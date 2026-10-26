namespace SaltmereCrossing;

/// <summary>The game's own flags, after "--" on the command line: --no-save.</summary>
public sealed class LaunchOptions
{
    public bool NoSave { get; private set; }

    public static LaunchOptions Parse(string[] args)
    {
        var options = new LaunchOptions();
        foreach (string arg in args)
        {
            if (arg == "--no-save")
                options.NoSave = true;
        }
        return options;
    }

    public static LaunchOptions FromCommandLine() => Parse(Godot.OS.GetCmdlineUserArgs());
}
