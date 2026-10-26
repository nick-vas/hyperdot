namespace SaltmereCrossing;

using System;
using System.Collections.Generic;
using System.Globalization;

/// <summary>One criterion of a choice's needs: a flag, an operator ("!", "=", "&lt;", "&lt;=", "&gt;", "&gt;=") and a number.</summary>
public sealed record Criterion(string Key, string Op, int Value);

/// <summary>
/// A choice's needs, in the kit's criteria grammar (the data runner checks the syntax): criteria joined by ";", each
/// "!flag" (the flag is 0) or "flag op number" with op one of = &lt; &lt;= &gt; &gt;=. Empty needs always hold.
/// </summary>
public static class Conditions
{
    // Two-letter operators first, so "<=" is not read as "<" followed by "=".
    private static readonly string[] Operators = { "<=", ">=", "=", "<", ">" };

    /// <summary>The criteria of a text; "!" is op "!" with value 0.</summary>
    public static List<Criterion> Parse(string text)
    {
        var output = new List<Criterion>();
        foreach (string part in text.Split(';'))
        {
            string item = part.Trim();
            if (item.Length == 0)
                continue;
            if (item.StartsWith('!'))
            {
                output.Add(new Criterion(item.Substring(1).Trim(), "!", 0));
                continue;
            }
            foreach (string op in Operators)
            {
                int at = item.IndexOf(op, StringComparison.Ordinal);
                if (at > 0)
                {
                    output.Add(new Criterion(item.Substring(0, at).Trim(), op, ToInt(item.Substring(at + op.Length).Trim())));
                    break;
                }
            }
        }
        return output;
    }

    /// <summary>Whether every criterion holds for the flags (a missing flag is 0).</summary>
    public static bool Holds(string text, IReadOnlyDictionary<string, int> flags)
    {
        foreach (Criterion criterion in Parse(text))
        {
            int value = flags.TryGetValue(criterion.Key, out int v) ? v : 0;
            bool ok = criterion.Op switch
            {
                "!" => value == 0,
                "=" => value == criterion.Value,
                "<" => value < criterion.Value,
                "<=" => value <= criterion.Value,
                ">" => value > criterion.Value,
                ">=" => value >= criterion.Value,
                _ => false,
            };
            if (!ok)
                return false;
        }
        return true;
    }

    /// <summary>The flags a text reads.</summary>
    public static List<string> Keys(string text)
    {
        var output = new List<string>();
        foreach (Criterion criterion in Parse(text))
            output.Add(criterion.Key);
        return output;
    }

    /// <summary>The leading whole number of a text, as GDScript's int() reads it; 0 when there is none.</summary>
    private static int ToInt(string text)
    {
        int end = 0;
        if (end < text.Length && (text[end] == '-' || text[end] == '+'))
            end++;
        while (end < text.Length && char.IsAsciiDigit(text[end]))
            end++;
        return int.TryParse(text.AsSpan(0, end), NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out int value) ? value : 0;
    }
}
