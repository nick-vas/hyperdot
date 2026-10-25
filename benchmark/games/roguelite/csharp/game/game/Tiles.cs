namespace Wickerdeep;

using Godot;

/// <summary>
/// The floor's walls and stones, drawn once per floor (and again when the stairs open): they never move, so they are not
/// drawn with the creatures every frame.
/// </summary>
public partial class Tiles : Node2D
{
    private const int TileSize = 22;
    private static readonly Color WallColor = new(0.13f, 0.11f, 0.15f);
    private static readonly Color EdgeColor = new(0.24f, 0.2f, 0.27f);
    private static readonly Color FloorColor = new(0.33f, 0.29f, 0.25f);
    private static readonly Color StoneColor = new(0.37f, 0.33f, 0.28f);
    private static readonly Color StairsShut = new(0.25f, 0.22f, 0.3f);
    private static readonly Color StairsOpen = new(0.98f, 0.78f, 0.36f);

    private Dungeon? _dungeon;
    private World? _world;

    public void ShowDungeon(Dungeon dungeon, World world)
    {
        _dungeon = dungeon;
        _world = world;
        QueueRedraw();
    }

    public override void _Draw()
    {
        if (_dungeon == null)
            return;
        Dungeon dungeon = _dungeon;
        DrawRect(new Rect2(new Vector2(-6, -6), new Vector2(dungeon.Width * TileSize + 12, dungeon.Height * TileSize + 12)), WallColor);
        for (int y = 0; y < dungeon.Height; y++)
        {
            for (int x = 0; x < dungeon.Width; x++)
            {
                var cell = new Vector2I(x, y);
                var rect = new Rect2(new Vector2(x * TileSize, y * TileSize), new Vector2(TileSize, TileSize));
                if (dungeon.IsFloor(cell))
                    DrawRect(rect, (x + y) % 2 == 0 ? StoneColor : FloorColor);
                else if (TouchesFloor(cell))
                    DrawRect(rect.Grow(-2), EdgeColor);
            }
        }
        var stairs = new Rect2(new Vector2(dungeon.Stairs.X, dungeon.Stairs.Y) * TileSize, new Vector2(TileSize, TileSize));
        bool open = _world != null && _world.StairsOpen;
        DrawRect(stairs.Grow(-2), open ? StairsOpen : StairsShut);
        for (int step = 0; step < 3; step++)
            DrawLine(stairs.Position + new Vector2(4, 6 + step * 5), stairs.Position + new Vector2(TileSize - 4, 6 + step * 5), WallColor, 2f);
    }

    private bool TouchesFloor(Vector2I cell)
    {
        foreach (Vector2I dir in Dungeon.Dirs)
        {
            if (_dungeon!.IsFloor(cell + dir))
                return true;
        }
        return false;
    }
}
