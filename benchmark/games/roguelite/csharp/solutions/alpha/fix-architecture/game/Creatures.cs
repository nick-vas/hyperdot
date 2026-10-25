namespace Wickerdeep;

using System.Collections.Generic;
using Godot;

/// <summary>
/// The wick and the enemies, drawn each frame where they are sliding between cells, and the rings left where an enemy
/// was snuffed. One node draws them all, so a swarm of hundreds costs one draw pass, not hundreds of nodes.
/// </summary>
public partial class Creatures : Node2D
{
    private const int TileSize = 22;
    private const int FlashTicks = 6;
    /// <summary>Seconds a snuffed enemy's ring takes to fade.</summary>
    private const float PopSeconds = 0.4f;
    private static readonly Dictionary<string, Color> KindColors = new()
    {
        ["shade"] = new Color(0.55f, 0.36f, 0.78f),
        ["bat"] = new Color(0.86f, 0.47f, 0.24f),
        ["brute"] = new Color(0.72f, 0.24f, 0.2f),
    };
    private static readonly Color EyeColor = new(1f, 0.9f, 0.6f);
    private static readonly Color GlowColor = new(1f, 0.8f, 0.4f, 0.07f);

    /// <summary>A ring where an enemy was snuffed: where, and how long ago.</summary>
    private sealed class Ring
    {
        public Vector2 At;
        public float Age;
    }

    private readonly List<Ring> _pops = new();
    private Texture2D _wickTexture = null!;
    private World? _world;

    public override void _Ready()
    {
        _wickTexture = GD.Load<Texture2D>("res://art/wick.png");
    }

    public void ShowWorld(World world)
    {
        _world = world;
        _pops.Clear();
        QueueRedraw();
    }

    /// <summary>A ring where an enemy was snuffed.</summary>
    public void Pop(Vector2I cell)
    {
        _pops.Add(new Ring { At = (new Vector2(cell.X, cell.Y) + new Vector2(0.5f, 0.5f)) * TileSize });
    }

    public void Advance(float delta)
    {
        foreach (Ring ring in _pops)
            ring.Age += delta;
        _pops.RemoveAll(ring => ring.Age >= PopSeconds);
        QueueRedraw();
    }

    public override void _Draw()
    {
        if (_world == null)
            return;
        World world = _world;
        Vector2 glow = Place(world.Wick);
        DrawCircle(glow, TileSize * 2.6f, GlowColor);
        foreach (Actor enemy in world.Enemies)
        {
            Vector2 at = Place(enemy);
            Color color = KindColors.TryGetValue(enemy.Kind, out Color kindColor) ? kindColor : Colors.Gray;
            if (world.Tick - enemy.HitAt < FlashTicks)
                color = Colors.White;
            switch (enemy.Kind)
            {
                case "bat":
                    DrawColoredPolygon(new[] { at + new Vector2(-9, -4), at + new Vector2(9, -4), at + new Vector2(0, 7) }, color);
                    break;
                case "brute":
                    DrawRect(new Rect2(at - new Vector2(9, 9), new Vector2(18, 18)), color);
                    break;
                default:
                    DrawCircle(at, 8f, color);
                    break;
            }
            if (enemy.Alert > 0)
            {
                DrawCircle(at + new Vector2(-3, -2), 1.6f, EyeColor);
                DrawCircle(at + new Vector2(3, -2), 1.6f, EyeColor);
            }
        }
        Color wickColor = world.Wick.Mercy > 0 && world.Tick % 8 < 4 ? new Color(1, 1, 1, 0.45f) : Colors.White;
        DrawTexture(_wickTexture, glow - _wickTexture.GetSize() / 2f, wickColor);
        foreach (Ring ring in _pops)
        {
            float t = ring.Age / PopSeconds;
            DrawArc(ring.At, 6f + t * 16f, 0f, Mathf.Tau, 20, new Color(1f, 0.75f, 0.35f, 1f - t), 2f);
        }
    }

    /// <summary>Where an actor is drawn: sliding from the cell it left to its cell over one step's ticks.</summary>
    private Vector2 Place(Actor actor)
    {
        float t = Mathf.Clamp((float)(_world!.Tick - actor.MovedAt) / Mathf.Max(actor.MoveTicks, 1f), 0f, 1f);
        var from = new Vector2(actor.FromCell.X, actor.FromCell.Y);
        var to = new Vector2(actor.Cell.X, actor.Cell.Y);
        return (from.Lerp(to, t) + new Vector2(0.5f, 0.5f)) * TileSize;
    }
}
