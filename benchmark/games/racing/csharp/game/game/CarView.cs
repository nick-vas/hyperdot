namespace Cinderloop;

using Godot;

/// <summary>A car drawn from above: a body, a windscreen and four wheels, pointing along +x. A ghost is drawn as an outline.</summary>
public partial class CarView : Node2D
{
    public const float Length = 40f;
    public const float Width = 22f;

    private static readonly Vector2[] Wheels = { new(-12, -12), new(12, -12), new(-12, 12), new(12, 12) };

    private Color _color = new("#f2c14e");
    private bool _ghost;

    public Color Color
    {
        get => _color;
        set
        {
            _color = value;
            QueueRedraw();
        }
    }

    public bool Ghost
    {
        get => _ghost;
        set
        {
            _ghost = value;
            QueueRedraw();
        }
    }

    public override void _Draw()
    {
        Vector2 half = new Vector2(Length, Width) / 2f;
        var body = new Rect2(-half, half * 2f);
        if (_ghost)
        {
            DrawRect(body, _color, false, 3f);
            return;
        }
        foreach (Vector2 wheel in Wheels)
            DrawRect(new Rect2(wheel - new Vector2(6, 3), new Vector2(12, 6)), new Color("#1b1b1b"));
        DrawRect(body, _color);
        DrawRect(new Rect2(new Vector2(3, -8), new Vector2(8, 16)), new Color("#2b3a4a"));
        DrawRect(new Rect2(new Vector2(-18, -3), new Vector2(14, 6)), _color.Lightened(0.35f));
        DrawRect(body, _color.Darkened(0.4f), false, 2f);
    }
}
