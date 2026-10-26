namespace Duskhive;

using System.Globalization;
using System.Text;

/// <summary>
/// Fills the %s, %d and %02d of a translated text in order, and turns %% into %. The translation table uses Godot's
/// placeholders, which both the GDScript and the C# version of the game share; numbers are written with the
/// invariant culture.
/// </summary>
public static class TextFormat
{
    public static string Fill(string pattern, params object[] values)
    {
        var text = new StringBuilder(pattern.Length + 16);
        int next = 0;
        for (int i = 0; i < pattern.Length; i++)
        {
            if (pattern[i] != '%' || i + 1 >= pattern.Length)
            {
                text.Append(pattern[i]);
                continue;
            }
            char kind = pattern[i + 1];
            if (kind == '%')
            {
                text.Append('%');
                i++;
            }
            else if ((kind == 's' || kind == 'd') && next < values.Length)
            {
                text.Append(System.Convert.ToString(values[next++], CultureInfo.InvariantCulture));
                i++;
            }
            else if (kind == '0' && i + 3 < pattern.Length && char.IsDigit(pattern[i + 2]) && pattern[i + 3] == 'd' && next < values.Length)
            {
                int width = pattern[i + 2] - '0';
                text.Append(System.Convert.ToInt64(values[next++], CultureInfo.InvariantCulture).ToString("D" + width, CultureInfo.InvariantCulture));
                i += 3;
            }
            else
            {
                text.Append(pattern[i]);
            }
        }
        return text.ToString();
    }
}
