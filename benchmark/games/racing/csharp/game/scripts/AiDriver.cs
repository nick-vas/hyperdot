namespace Cinderloop;

using Godot;
using static Cinderloop.Maths;

/// <summary>
/// Drives a car along the racing line: it steers for a point ahead on the line (further ahead the faster it goes) and
/// keeps to the track's speed profile, scaled by its pace, lifting and braking before the bends. The rivals and the bot
/// are all this driver; only pace and their line differ.
/// </summary>
public sealed class AiDriver
{
    /// <summary>How far ahead it aims, in pixels, and how much further per pixel a second of speed.</summary>
    public const double AimBase = 70.0;
    public const double AimPerSpeed = 0.3;
    /// <summary>Steering per radian between the heading and the aim.</summary>
    public const double SteerGain = 2.4;
    /// <summary>Over the planned speed by this much, it brakes instead of lifting.</summary>
    public const double BrakeMargin = 40.0;

    public AiDriver(double pace = 1.0, double offset = 0.0)
    {
        Pace = pace;
        LineOffset = offset;
    }

    /// <summary>1 drives the profile as planned; a rival at 0.9 takes every part of the lap at nine tenths.</summary>
    public double Pace { get; set; }
    /// <summary>Pixels to the right of the centre line it drives on.</summary>
    public double LineOffset { get; set; }

    /// <summary>Throttle (x) and steering (y) for this tick.</summary>
    public Vector2 Decide(Car car, Track track)
    {
        double aimDistance = AimBase + AimPerSpeed * MaxF(car.Speed, 0.0);
        Vector2 target = PointAhead(track, car.Index, aimDistance);
        double wanted = (target - car.Position).Angle();
        double steer = ClampF(AngleDifference(car.Heading, wanted) * SteerGain, -1.0, 1.0);
        // The slowest planned speed over the stretch the car covers in the next half second.
        double limit = double.PositiveInfinity;
        int reach = System.Math.Max((int)(MaxF(car.Speed, 0.0) * 0.5 / MaxF(track.SegmentLength(car.Index), 1.0)), 1);
        for (int k = 0; k < reach + 1; k++)
            limit = MinF(limit, track.SpeedProfile[PosMod(car.Index + k, track.PointCount())]);
        limit *= Pace;
        double throttle = Pace;
        if (car.Speed > limit + BrakeMargin)
            throttle = -1.0;
        else if (car.Speed > limit)
            throttle = 0.0;
        return new Vector2((float)throttle, (float)steer);
    }

    private Vector2 PointAhead(Track track, int from, double distance)
    {
        int i = from;
        double left = distance;
        while (left > track.SegmentLength(PosMod(i, track.PointCount())))
        {
            left -= track.SegmentLength(PosMod(i, track.PointCount()));
            i += 1;
        }
        Vector2 a = track.Point(i);
        Vector2 b = track.Point(i + 1);
        Vector2 onLine = a.Lerp(b, (float)(left / MaxF(a.DistanceTo(b), 0.001)));
        return onLine + track.Tangent(i).Orthogonal() * (float)LineOffset;
    }
}
