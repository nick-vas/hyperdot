namespace Cinderloop;

using System;

/// <summary>
/// The engine's scalar helpers (wrapf, posmod, angle_difference, roundi...) as Godot's C++ defines them, so the race
/// gives the same numbers as the GDScript version tick for tick. Mathf's own versions differ at the edges: its rounding
/// goes to even, and Math.Max and Math.Min treat zero's sign and NaN their own way.
/// </summary>
public static class Maths
{
    private const double CmpEpsilon = 0.00001;

    public static double MinF(double a, double b) => a < b ? a : b;

    public static double MaxF(double a, double b) => a > b ? a : b;

    public static double ClampF(double value, double min, double max) => value < min ? min : (value > max ? max : value);

    /// <summary>-1, 0 or 1.</summary>
    public static double SignF(double value) => value > 0.0 ? 1.0 : (value < 0.0 ? -1.0 : 0.0);

    /// <summary>Rounded half away from zero, as C's round().</summary>
    public static int RoundI(double value) => (int)Math.Round(value, MidpointRounding.AwayFromZero);

    /// <summary>A remainder that is never negative for a positive divisor.</summary>
    public static int PosMod(int value, int divisor)
    {
        int result = value % divisor;
        if ((result < 0 && divisor > 0) || (result > 0 && divisor < 0))
            result += divisor;
        return result;
    }

    public static double FPosMod(double value, double divisor)
    {
        double result = value % divisor;
        if ((result < 0 && divisor > 0) || (result > 0 && divisor < 0))
            result += divisor;
        return result + 0.0;
    }

    public static bool IsEqualApprox(double a, double b)
    {
        if (a == b)
            return true;
        double tolerance = CmpEpsilon * Math.Abs(a);
        if (tolerance < CmpEpsilon)
            tolerance = CmpEpsilon;
        return Math.Abs(a - b) < tolerance;
    }

    /// <summary>A value wrapped into [min, max).</summary>
    public static double WrapF(double value, double min, double max)
    {
        double range = max - min;
        if (Math.Abs(range) < CmpEpsilon)
            return min;
        double result = value - (range * Math.Floor((value - min) / range));
        if (IsEqualApprox(result, max))
            return min;
        return result;
    }

    /// <summary>The shortest turn from one angle to another, in radians.</summary>
    public static double AngleDifference(double from, double to)
    {
        double difference = (to - from) % Math.Tau;
        return ((2.0 * difference) % Math.Tau) - difference;
    }

    /// <summary>A value rounded to the nearest multiple of step.</summary>
    public static double Snapped(double value, double step) => step != 0 ? Math.Floor(value / step + 0.5) * step : value;
}
