namespace Duskhive;

using Godot;

/// <summary>
/// Autoload: the unobscured part of the screen in viewport (canvas) coordinates, and a fake notch for desktop tests.
/// --safe-area=left,top,right,bottom (window pixels) after "--" overrides the platform's answer, so a desktop run or a
/// CI check can show what a phone with a notch would hide. The kit's layout runner calls SetInsets with each profile's.
/// </summary>
public partial class SafeArea : Node
{
    [Signal]
    public delegate void ChangedEventHandler();

    private Rect2I _override;

    public override void _Ready()
    {
        foreach (string arg in OS.GetCmdlineUserArgs())
        {
            if (!arg.StartsWith("--safe-area=", System.StringComparison.Ordinal))
                continue;
            string[] p = arg.Substring("--safe-area=".Length).Split(',');
            if (p.Length == 4)
                SetInsets(p[0].ToInt(), p[1].ToInt(), p[2].ToInt(), p[3].ToInt());
        }
        GetTree().Root.SizeChanged += OnSizeChanged;
    }

    public override void _ExitTree() => GetTree().Root.SizeChanged -= OnSizeChanged;

    private void OnSizeChanged() => EmitSignal(SignalName.Changed);

    /// <summary>Insets in window pixels; all zero removes the fake notch.</summary>
    public void SetInsets(int left, int top, int right, int bottom)
    {
        Vector2I window = GetTree().Root.Size;
        _override = left + top + right + bottom > 0 ? new Rect2I(left, top, window.X - left - right, window.Y - top - bottom) : new Rect2I();
        EmitSignal(SignalName.Changed);
    }

    /// <summary>Safe rectangle in window pixels.</summary>
    public Rect2I WindowRect()
    {
        var window = new Rect2I(Vector2I.Zero, GetTree().Root.Size);
        if (_override.HasArea())
            return _override;
        if (!OS.HasFeature("mobile"))
            return window;
        // Screen coordinates; a mobile game is full screen, so the window starts at the screen origin.
        Rect2I safe = DisplayServer.GetDisplaySafeArea();
        safe.Position -= DisplayServer.WindowGetPosition();
        return safe.Intersection(window);
    }

    /// <summary>Safe rectangle in the coordinates Controls use (after stretch).</summary>
    public Rect2 CanvasRect()
    {
        Rect2I window = WindowRect();
        return GetTree().Root.GetFinalTransform().AffineInverse() * new Rect2(window.Position, window.Size);
    }
}
