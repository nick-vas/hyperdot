namespace Bramblegate;

using System.Collections.Generic;
using Godot;

/// <summary>
/// Draws the battle: the grid, rocks, the gate, the pests' route, towers, pests, shots and the rings left where
/// something happened. It only reads the battle; the game node decides.
/// </summary>
public partial class Field : Node2D
{
    public static readonly Vector2 Origin = new(66, 120);
    public const float CellSize = 54f;
    public const float PopSeconds = 0.4f;
    private static readonly Color[] Grass = { new(0.2f, 0.32f, 0.16f), new(0.22f, 0.35f, 0.18f) };
    private static readonly Color RockColor = new(0.36f, 0.33f, 0.3f);
    private static readonly Color GateColor = new(0.12f, 0.2f, 0.09f);
    private static readonly Color RouteColor = new(0.95f, 0.85f, 0.55f, 0.35f);
    private static readonly Dictionary<string, Color> TowerColors = new()
    {
        ["thorn"] = new Color(0.55f, 0.85f, 0.35f),
        ["puff"] = new Color(0.95f, 0.85f, 0.35f),
        ["acorn"] = new Color(0.7f, 0.45f, 0.25f),
    };
    private static readonly Dictionary<string, Color> EnemyColors = new()
    {
        ["aphid"] = new Color(0.6f, 0.95f, 0.5f),
        ["beetle"] = new Color(0.25f, 0.3f, 0.55f),
        ["moth"] = new Color(0.85f, 0.75f, 0.95f),
        ["slug_queen"] = new Color(0.75f, 0.35f, 0.6f),
    };

    private sealed class Ring
    {
        public Vector2 At;
        public Color Color;
        public float Left;
    }

    private readonly List<Ring> _pops = new();

    public Battle? Battle { get; private set; }
    public Vector2I Selected { get; set; } = new(-1, -1);

    public void ShowBattle(Battle battle)
    {
        Battle = battle;
        _pops.Clear();
        QueueRedraw();
    }

    /// <summary>A battle position (in cells) on screen.</summary>
    public static Vector2 ToScreen(Vector2 pos) => Origin + pos * CellSize;

    public static Vector2 CellCentre(Vector2I cell) => ToScreen(Enemy.Centre(cell));

    public static Vector2I CellAt(Vector2 local)
    {
        Vector2 at = (local - Origin) / CellSize;
        return new Vector2I(Mathf.FloorToInt(at.X), Mathf.FloorToInt(at.Y));
    }

    /// <summary>A ring that grows and fades where something happened.</summary>
    public void Pop(Vector2 at, Color color)
    {
        _pops.Add(new Ring { At = at, Color = color, Left = PopSeconds });
        QueueRedraw();
    }

    public override void _Process(double delta)
    {
        if (_pops.Count == 0)
            return;
        foreach (Ring ring in _pops)
            ring.Left -= (float)delta;
        _pops.RemoveAll(ring => ring.Left <= 0f);
        QueueRedraw();
    }

    public override void _Draw()
    {
        if (Battle == null)
            return;
        PathMap map = Battle.Map;
        for (int y = 0; y < map.Size.Y; y++)
        {
            for (int x = 0; x < map.Size.X; x++)
            {
                var cell = new Vector2I(x, y);
                var rect = new Rect2(Origin + new Vector2(x, y) * CellSize, new Vector2(CellSize, CellSize));
                DrawRect(rect, Grass[(x + y) % 2]);
                if (map.IsRock(cell))
                    DrawRect(rect.Grow(-4), RockColor);
            }
        }
        DrawRect(new Rect2(Origin + new Vector2(map.Gate.X, map.Gate.Y) * CellSize, new Vector2(CellSize, CellSize)).Grow(-6), GateColor);
        foreach (Vector2I step in map.Route)
            DrawCircle(CellCentre(step), 5f, RouteColor);
        if (Battle.Towers.Has(Selected))
        {
            Tower chosen = Battle.Towers[Selected];
            float reach = (float)Battle.Catalog.Stats(chosen.Id, chosen.Level).Range;
            DrawArc(CellCentre(Selected), reach * CellSize, 0f, Mathf.Tau, 48, new Color(1, 1, 1, 0.5f), 2f);
        }
        foreach (Tower tower in Battle.Towers)
            DrawTower(tower);
        foreach (Enemy enemy in Battle.Enemies)
            DrawEnemy(enemy);
        foreach (Shot shot in Battle.Shots)
        {
            Color color = TowerColors.TryGetValue(shot.Tower, out Color found) ? found : Colors.White;
            DrawCircle(ToScreen(shot.Pos), shot.Splash > 0.0 ? 5f : 3.5f, color.Lightened(0.3f));
        }
        foreach (Ring ring in _pops)
        {
            float t = 1f - ring.Left / PopSeconds;
            Color color = ring.Color;
            color.A = 1f - t;
            DrawArc(ring.At, 10f + 30f * t, 0f, Mathf.Tau, 32, color, 3f);
        }
    }

    private void DrawTower(Tower tower)
    {
        Vector2 at = CellCentre(tower.Cell);
        float k = CellSize / 64f;
        Color color = TowerColors.TryGetValue(tower.Id, out Color found) ? found : Colors.White;
        switch (tower.Id)
        {
            case "thorn":
                DrawColoredPolygon(new[] { at + new Vector2(0, -24) * k, at + new Vector2(20, 18) * k, at + new Vector2(-20, 18) * k }, color);
                break;
            case "puff":
                DrawCircle(at, 22f * k, color);
                DrawCircle(at, 10f * k, color.Darkened(0.3f));
                break;
            default:
                DrawRect(new Rect2(at - new Vector2(20, 20) * k, new Vector2(40, 40) * k), color);
                DrawCircle(at, 9f * k, color.Darkened(0.4f));
                break;
        }
        if (Selected == tower.Cell)
            DrawRect(new Rect2(at - new Vector2(28, 28) * k, new Vector2(56, 56) * k), Colors.White, false, 2f);
        for (int i = 0; i < tower.Level; i++)
            DrawCircle(at + new Vector2(-12 + 12 * i, 26) * k, 3.5f, new Color(1, 1, 1, 0.9f));
    }

    private void DrawEnemy(Enemy enemy)
    {
        Vector2 at = ToScreen(enemy.Pos);
        float radius = (float)Battle!.Catalog.Enemies[enemy.Id].Size * CellSize;
        DrawCircle(at, radius, EnemyColors.TryGetValue(enemy.Id, out Color found) ? found : Colors.White);
        if (enemy.SlowTicks > 0)
            DrawArc(at, radius + 3f, 0f, Mathf.Tau, 24, new Color(0.95f, 0.85f, 0.35f, 0.8f), 2f);
        float share = Mathf.Clamp((float)enemy.Hp / enemy.MaxHp, 0f, 1f);
        DrawRect(new Rect2(at + new Vector2(-radius, -radius - 8), new Vector2(radius * 2f, 4)), new Color(0.2f, 0.05f, 0.05f));
        DrawRect(new Rect2(at + new Vector2(-radius, -radius - 8), new Vector2(radius * 2f * share, 4)), new Color(0.9f, 0.25f, 0.2f));
    }
}
