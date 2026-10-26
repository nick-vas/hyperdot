namespace Duskhive;

using Godot;

/// <summary>A MarginContainer that keeps its children inside SafeArea. Anchor it full rect.</summary>
public partial class SafeMargins : MarginContainer
{
    private SafeArea? _safeArea;

    /// <summary>Margin added on every side, beyond the safe area.</summary>
    [Export]
    public int Extra { get; set; }

    public override void _Ready()
    {
        _safeArea = GetNodeOrNull<SafeArea>("/root/SafeArea");
        if (_safeArea == null)
            return;
        _safeArea.Changed += Apply;
        Apply();
    }

    public override void _ExitTree()
    {
        if (_safeArea != null)
            _safeArea.Changed -= Apply;
    }

    private void Apply()
    {
        Rect2 view = GetViewportRect();
        Rect2 safe = _safeArea!.CanvasRect();
        AddThemeConstantOverride("margin_left", Mathf.CeilToInt(safe.Position.X - view.Position.X) + Extra);
        AddThemeConstantOverride("margin_top", Mathf.CeilToInt(safe.Position.Y - view.Position.Y) + Extra);
        AddThemeConstantOverride("margin_right", Mathf.CeilToInt(view.End.X - safe.End.X) + Extra);
        AddThemeConstantOverride("margin_bottom", Mathf.CeilToInt(view.End.Y - safe.End.Y) + Extra);
    }
}
