namespace Duskhive;

using System;

/// <summary>What a stretch of time away paid: the seconds counted and the glow they earned.</summary>
public readonly record struct TimeAway(double Seconds, double Glow);

/// <summary>
/// Progress while the game was closed, from the time saved and the time now, both given by the caller (scripts/ never
/// reads the clock, so this is testable and the same on every machine). A clock set back pays nothing, the time paid is
/// capped, and the time kept for the next save never goes back, so a clock put right again does not pay twice.
/// </summary>
public static class Offline
{
    /// <summary>The seconds away that are paid for.</summary>
    public static double SecondsAway(double savedAt, double now, double cap)
    {
        return Math.Clamp(now - savedAt, 0.0, cap);
    }

    /// <summary>The time to keep for the next save: the latest the game has seen.</summary>
    public static double SeenAt(double savedAt, double now)
    {
        return now;
    }

    /// <summary>Pays an economy for the time away; the seconds paid and the glow they earned.</summary>
    public static TimeAway Apply(Economy economy, double savedAt, double now)
    {
        double seconds = SecondsAway(savedAt, now, economy.Catalog.Setting("offline_cap_seconds"));
        return new TimeAway(seconds, economy.Tick(seconds));
    }
}
