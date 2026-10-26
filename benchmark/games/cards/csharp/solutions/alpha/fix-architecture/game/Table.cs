namespace Lanternfen;

using System.Collections.Generic;
using Godot;

/// <summary>
/// Draws the table: the rival's row of three lanes above the player's, each wisp as a card with its name, power and
/// guard, and a ring that spreads where a wisp falls. It reads the duel; it never changes it.
/// </summary>
public partial class Table : Node2D
{
    public static readonly Vector2 CardSize = new(150, 110);
    public static readonly float[] LaneX = { 440f, 640f, 840f };
    /// <summary>The rows' centres: the rival's (seat 1) above, the player's (seat 0) below.</summary>
    public static readonly float[] RowY = { 385f, 205f };
    public static readonly Color[] SeatColors = { new(0.2f, 0.55f, 0.5f), new(0.45f, 0.3f, 0.6f) };
    public static readonly Color LaneColor = new(1, 1, 1, 0.12f);
    public const float PopSeconds = 0.4f;

    /// <summary>A ring where a wisp fell, and how long ago.</summary>
    private sealed class Ring
    {
        public Vector2 At;
        public float Age;
    }

    private readonly List<Ring> _pops = new();

    public Duel? Duel { get; private set; }
    public Cards? Cards { get; private set; }

    public void ShowDuel(Duel shown, Cards catalogue)
    {
        Duel = shown;
        Cards = catalogue;
        _pops.Clear();
        QueueRedraw();
    }

    public static Vector2 LaneCenter(int seat, int lane) => new(LaneX[lane], RowY[seat]);

    /// <summary>A ring where a wisp fell.</summary>
    public void Pop(int seat, int lane)
    {
        _pops.Add(new Ring { At = LaneCenter(seat, lane) });
        QueueRedraw();
    }

    public override void _PhysicsProcess(double delta)
    {
        if (_pops.Count == 0)
            return;
        foreach (Ring ring in _pops)
            ring.Age += (float)delta;
        _pops.RemoveAll(ring => ring.Age >= PopSeconds);
        QueueRedraw();
    }

    public override void _Draw()
    {
        if (Duel == null || Cards == null)
            return;
        Font font = ThemeDB.FallbackFont;
        for (int seat = 0; seat < 2; seat++)
        {
            for (int lane = 0; lane < Keeper.Lanes; lane++)
            {
                var rect = new Rect2(LaneCenter(seat, lane) - CardSize / 2f, CardSize);
                Wisp? wisp = Duel.Keepers[seat].Row[lane];
                if (wisp == null)
                {
                    DrawRect(rect, LaneColor, false, 2f);
                    continue;
                }
                DrawRect(rect, SeatColors[seat]);
                DrawRect(rect, SeatColors[seat].Lightened(0.4f), false, 2f);
                string nameText = Tr(Cards.Get(wisp.Id).Name);
                DrawString(font, rect.Position + new Vector2(0, 30), nameText, HorizontalAlignment.Center, CardSize.X, 16);
                DrawString(font, rect.Position + new Vector2(0, 84), $"{wisp.Power} / {wisp.Guard}", HorizontalAlignment.Center, CardSize.X, 30);
            }
        }
        foreach (Ring ring in _pops)
        {
            float t = ring.Age / PopSeconds;
            DrawArc(ring.At, 30f + 60f * t, 0f, Mathf.Tau, 32, new Color(1f, 0.8f, 0.4f, 1f - t), 4f);
        }
    }
}
