namespace Duskhive;

using System;
using System.Globalization;

/// <summary>
/// Big numbers. Glow and costs are doubles: exact up to 2^53, past it kept to about 16 significant digits (a relative
/// error under 1e-12 is the game's tolerance, tested), and the screen shows three. They are printed with a short name
/// per thousand (K, M, B ... Dc), then two letters (aa, ab ... zz), never in scientific notation. Nothing here calls
/// Math.Pow or Math.Log, whose last bit can differ between machines: powers are multiplied out. Text is formatted with
/// the invariant culture, so a machine that writes 1,5 for one and a half prints the same as any other.
/// </summary>
public static class Numbers
{
    private static readonly string[] Suffixes = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" };

    /// <summary>The most glow the game keeps: a double would reach infinity at 1.8e308.</summary>
    public const double Max = 1e300;

    /// <summary>How far a sum of doubles may drift from the exact value, relative to it: what the tests allow.</summary>
    public const double Tolerance = 1e-12;

    /// <summary>1000^k for every group up to Max, each parsed from its decimal text so that 1e33 is exactly the double 1e33.</summary>
    private static readonly double[] Thousands = MakeThousands();

    /// <summary>
    /// A number as the screen shows it: whole numbers below 1000 (one decimal below 10), then three significant digits
    /// and a suffix, rounded down so the screen never promises glow the player does not have.
    /// </summary>
    public static string Format(double value)
    {
        if (double.IsNaN(value) || value <= 0.0)
            return "0";
        value = Math.Min(value, Max);
        if (value < 10.0)
        {
            double tenths = Math.Floor(value * 10.0 + 1e-9) / 10.0;
            return tenths == Math.Floor(tenths) ? Whole(tenths) : Fixed(tenths, "0.0");
        }
        if (value < 1000.0)
            return Whole(Math.Floor(value + 1e-9));
        int group = GroupOf(value);
        double mantissa = value / Thousand(group);
        string digits;
        if (mantissa >= 100.0)
            digits = Whole(Math.Floor(mantissa + 1e-9));
        else if (mantissa >= 10.0)
            digits = Fixed(Math.Floor(mantissa * 10.0 + 1e-9) / 10.0, "0.0");
        else
            digits = Fixed(Math.Floor(mantissa * 100.0 + 1e-9) / 100.0, "0.00");
        return digits + Suffix(group);
    }

    /// <summary>The name of 1000^group: the short names first, then aa, ab ... az, ba ... (1e36 is aa).</summary>
    public static string Suffix(int group)
    {
        if (group < Suffixes.Length)
            return Suffixes[group];
        int n = group - Suffixes.Length;
        return new string(new[] { (char)('a' + n / 26 % 26), (char)('a' + n % 26) });
    }

    /// <summary>The largest k with 1000^k &lt;= value (0 below 1000).</summary>
    public static int GroupOf(double value)
    {
        int k = 0;
        while (k + 1 < Thousands.Length && value >= Thousand(k + 1))
            k++;
        return k;
    }

    /// <summary>1000^k, exact for every k a double can hold.</summary>
    public static double Thousand(int k) => Thousands[Math.Clamp(k, 0, Thousands.Length - 1)];

    /// <summary>base^exponent for a whole exponent, by squaring: the same result on every machine.</summary>
    public static double Power(double value, int exponent)
    {
        double result = 1.0;
        double b = value;
        long e = Math.Abs((long)exponent);
        while (e > 0)
        {
            if ((e & 1) != 0)
                result *= b;
            b *= b;
            e >>= 1;
        }
        return exponent >= 0 ? result : 1.0 / result;
    }

    /// <summary>A rate per second, as the screen shows it.</summary>
    public static string FormatRate(double perSecond) => Format(perSecond) + "/s";

    /// <summary>Whether two doubles agree within the game's tolerance.</summary>
    public static bool Close(double a, double b, double tolerance = Tolerance) =>
        Math.Abs(a - b) <= tolerance * Math.Max(Math.Abs(a), Math.Abs(b));

    private static double[] MakeThousands()
    {
        var thousands = new double[101];
        for (int i = 0; i < thousands.Length; i++)
            thousands[i] = double.Parse("1e" + (3 * i).ToString(CultureInfo.InvariantCulture), NumberStyles.Float, CultureInfo.InvariantCulture);
        return thousands;
    }

    private static string Whole(double value) => ((long)value).ToString(CultureInfo.InvariantCulture);

    private static string Fixed(double value, string format) => value.ToString(format, CultureInfo.InvariantCulture);
}
