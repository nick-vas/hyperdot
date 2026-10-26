namespace SaltmereCrossing;

using Godot;

/// <summary>
/// The river behind the text, drawn in code: night sky, water, the ferry with the stranger and the lantern, the fog of
/// the crossing and the far bank with its drowned tower. The lantern glows when the stranger's trust grows.
/// </summary>
public partial class Backdrop : Control
{
    private static readonly Color Sky = new(0.05f, 0.07f, 0.11f);
    private static readonly Color Water = new(0.07f, 0.13f, 0.17f);
    private static readonly Color WaterLine = new(0.12f, 0.2f, 0.25f);
    private static readonly Color Bank = new(0.03f, 0.05f, 0.06f);
    private static readonly Color Boat = new(0.24f, 0.16f, 0.1f);
    private static readonly Color Figure = new(0.5f, 0.53f, 0.56f);
    private static readonly Color Lantern = new(1.0f, 0.8f, 0.42f);

    private Texture2D _lanternTexture = null!;
    private int _chapter = 1;
    private float _glow;

    /// <summary>The chapter of the line shown: 1 the landing, 2 the crossing in fog, 3 the far bank.</summary>
    public int Chapter
    {
        get => _chapter;
        set
        {
            if (value != _chapter)
            {
                _chapter = value;
                QueueRedraw();
            }
        }
    }

    /// <summary>How brightly the lantern glows, 0 to 1; it fades on its own.</summary>
    public float Glow
    {
        get => _glow;
        set
        {
            if (!Mathf.IsEqualApprox(value, _glow))
            {
                _glow = value;
                QueueRedraw();
            }
        }
    }

    public override void _Ready()
    {
        _lanternTexture = GD.Load<Texture2D>("res://art/lantern.png");
    }

    public override void _Draw()
    {
        float w = Size.X;
        float h = Size.Y;
        float horizon = h * 0.42f;
        DrawRect(new Rect2(0, 0, w, horizon), Sky);
        DrawRect(new Rect2(0, horizon, w, h - horizon), Water);
        for (int i = 0; i < 6; i++)
        {
            float y = horizon + 24.0f + i * (h - horizon) / 6.0f;
            DrawLine(new Vector2(w * 0.08f * i, y), new Vector2(w * (0.4f + 0.08f * i), y), WaterLine, 2.0f);
        }
        if (Chapter == 1)
        {
            // The Hensmouth landing on the left: a jetty and the town's lights.
            DrawRect(new Rect2(0, horizon - 40, w * 0.3f, 40), Bank);
            for (int i = 0; i < 5; i++)
                DrawCircle(new Vector2(30 + i * 70, horizon - 54), 4.0f, Lantern.Darkened(0.3f));
        }
        if (Chapter == 3)
        {
            // The Greywick bank on the right and the broken tower in the shallows.
            DrawRect(new Rect2(w * 0.65f, horizon - 50, w * 0.35f, 50), Bank);
            DrawRect(new Rect2(w * 0.56f, horizon - 150, 46, 170), Bank);
            DrawColoredPolygon(new[] { new Vector2(w * 0.56f, horizon - 150), new Vector2(w * 0.56f + 46, horizon - 150), new Vector2(w * 0.56f + 30, horizon - 186) }, Bank);
        }
        DrawFerry(new Vector2(w * 0.74f, horizon + (h - horizon) * 0.35f));
        if (Chapter == 2)
            DrawRect(new Rect2(0, 0, w, h), new Color(0.6f, 0.65f, 0.7f, 0.28f));
    }

    private void DrawFerry(Vector2 at)
    {
        DrawColoredPolygon(new[] { at + new Vector2(-170, 0), at + new Vector2(170, 0), at + new Vector2(130, 34), at + new Vector2(-130, 34) }, Boat);
        // The stranger, seated at the bow, and the lantern on its pole at the stern.
        DrawRect(new Rect2(at + new Vector2(60, -58), new Vector2(34, 58)), Figure);
        DrawCircle(at + new Vector2(77, -72), 16.0f, Figure);
        DrawLine(at + new Vector2(-120, 0), at + new Vector2(-120, -90), Boat.Lightened(0.2f), 4.0f);
        Vector2 lamp = at + new Vector2(-120, -100);
        DrawCircle(lamp, 26.0f + 30.0f * Glow, new Color(Lantern, 0.12f + 0.3f * Glow));
        DrawTexture(_lanternTexture, lamp - _lanternTexture.GetSize() / 2.0f, new Color(1, 1, 1).Lerp(new Color(1.3f, 1.2f, 0.9f), Glow));
    }
}
