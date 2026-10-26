namespace Glimmerpit;

using System.Collections.Generic;
using Godot;

/// <summary>
/// Draws the pit from the client: the court and its pillars, every glimmer where this screen shows it (its own
/// predicted, the others interpolated), shots as fading beams, a ring where a glimmer was knocked out, and a white
/// flash on a glimmer that was hit. It decides nothing.
/// </summary>
public partial class CourtView : Node2D
{
    public const double BeamSeconds = 0.18;
    public const double PopSeconds = 0.45;
    public const double FlashSeconds = 0.15;

    private sealed class Beam
    {
        public Vector2 From;
        public Vector2 To;
        public Color Color;
        public double Left;
    }

    private sealed class Ring
    {
        public Vector2 At;
        public double Left;
    }

    private readonly List<Beam> _beams = new();
    private readonly List<Ring> _pops = new();
    private readonly Dictionary<int, double> _flashes = new();
    private readonly List<int> _flashSlots = new();

    public ArenaClient? Client { get; set; }
    public Vector2 Origin { get; set; } = Vector2.Zero;
    public Color[] Colors { get; set; } = System.Array.Empty<Color>();

    public void AddBeam(Vector2 from, Vector2 to, Color color) => _beams.Add(new Beam { From = from, To = to, Color = color, Left = BeamSeconds });

    public void Pop(Vector2 at) => _pops.Add(new Ring { At = at, Left = PopSeconds });

    public void FlashFighter(int slot) => _flashes[slot] = FlashSeconds;

    public override void _PhysicsProcess(double delta)
    {
        foreach (Beam b in _beams)
            b.Left -= delta;
        _beams.RemoveAll(b => b.Left <= 0.0);
        foreach (Ring p in _pops)
            p.Left -= delta;
        _pops.RemoveAll(p => p.Left <= 0.0);
        _flashSlots.Clear();
        _flashSlots.AddRange(_flashes.Keys);
        foreach (int slot in _flashSlots)
        {
            _flashes[slot] -= delta;
            if (_flashes[slot] <= 0.0)
                _flashes.Remove(slot);
        }
    }

    public override void _Draw()
    {
        if (Client == null)
            return;
        Court court = Client.View.Court;
        DrawRect(new Rect2(Origin, new Vector2(court.Width, court.Height)), new Color(0.1f, 0.09f, 0.13f));
        DrawRect(new Rect2(Origin, new Vector2(court.Width, court.Height)), new Color(0.45f, 0.4f, 0.55f), false, 4.0f);
        foreach (Rect2I wall in court.Walls)
            DrawRect(new Rect2(Origin + (Vector2)wall.Position, (Vector2)wall.Size), new Color(0.32f, 0.28f, 0.4f));
        foreach (Fighter f in Client.ShownFighters())
        {
            if (!f.Alive)
                continue;
            Vector2 at = Origin + f.Position();
            Color color = f.Slot < Colors.Length ? Colors[f.Slot] : Godot.Colors.White;
            DrawCircle(at, (float)Sim.Radius, _flashes.ContainsKey(f.Slot) ? Godot.Colors.White : color);
            DrawLine(at, at + f.Aim() * 30.0f, color.Lightened(0.4f), 4.0f);
            if (f.Slot == Client.Slot)
                DrawArc(at, (float)Sim.Radius + 6.0f, 0.0f, Mathf.Tau, 32, Godot.Colors.White, 2.0f);
        }
        foreach (Beam b in _beams)
        {
            float fade = (float)(b.Left / BeamSeconds);
            DrawLine(Origin + b.From, Origin + b.To, new Color(b.Color, fade), 3.0f);
        }
        foreach (Ring p in _pops)
        {
            float grown = 1.0f - (float)(p.Left / PopSeconds);
            DrawArc(Origin + p.At, 20.0f + grown * 50.0f, 0.0f, Mathf.Tau, 32, new Color(1.0f, 0.9f, 0.6f, 1.0f - grown), 4.0f);
        }
    }
}
