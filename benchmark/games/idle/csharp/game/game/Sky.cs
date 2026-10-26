namespace Duskhive;

using System;
using Godot;

/// <summary>The dusk behind the hive: motes of glow drifting up, more of them the more glow there is, drawn as circles.</summary>
public partial class Sky : Control
{
    private const int MostMotes = 48;

    private double _time;

    /// <summary>The glow to show; Game sets it every tick.</summary>
    public double Glow { get; set; }

    public override void _Process(double delta)
    {
        _time += delta;
        QueueRedraw();
    }

    public override void _Draw()
    {
        Vector2 area = Size;
        DrawRect(new Rect2(Vector2.Zero, area), new Color(0.07f, 0.06f, 0.12f));
        DrawCircle(new Vector2(area.X * 0.8f, area.Y * 0.12f), 60.0f, new Color(0.95f, 0.85f, 0.55f, 0.25f));
        int motes = Math.Clamp(4 + Digits(Glow) * 3, 4, MostMotes);
        for (int i = 0; i < motes; i++)
        {
            // Fixed lanes and phases, so the sky moves the same way every time.
            double lane = i * 0.618034 % 1.0;
            double rise = (_time * (0.02 + 0.01 * (i * 0.37 % 1.0)) + i * 0.13) % 1.0;
            var at = new Vector2((float)(lane * area.X + Math.Sin(_time + i) * 12.0), (float)(area.Y * (1.0 - rise)));
            DrawCircle(at, (float)(3.0 + i * 0.71 % 1.0 * 4.0), new Color(1.0f, 0.82f, 0.4f, (float)(0.35 + 0.4 * (1.0 - rise))));
        }
    }

    /// <summary>How many digits the whole glow has (at least one).</summary>
    private static int Digits(double glow)
    {
        int digits = 1;
        for (double tens = 10.0; tens <= glow && digits < MostMotes; tens *= 10.0)
            digits++;
        return digits;
    }
}
