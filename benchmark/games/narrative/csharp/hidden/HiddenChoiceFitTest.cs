namespace SaltmereCrossing.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-bug: every choice, in every language, fits its button in at most two lines (the
/// choice buttons' font at 22 px, 440 px of text in a 460 px column), and the French answers are still French.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenChoiceFitTest
{
    private const int FontSize = 22;
    private const float Width = 440.0f;

    [AfterTest]
    public void English()
    {
        TranslationServer.SetLocale("en");
    }

    private static int Lines(string text)
    {
        Font font = ThemeDB.FallbackFont;
        Vector2 size = font.GetMultilineStringSize(text, HorizontalAlignment.Center, Width, FontSize, -1, TextServer.LineBreakFlag.Mandatory | TextServer.LineBreakFlag.WordBound);
        return Mathf.RoundToInt(size.Y / font.GetHeight(FontSize));
    }

    [TestCase]
    public void Hidden_every_choice_fits_in_two_lines()
    {
        StoryGraph graph = StoryGraph.FromFiles();
        foreach (string locale in TranslationServer.GetLoadedLocales())
        {
            TranslationServer.SetLocale(locale);
            foreach (string id in graph.ChoiceIds)
            {
                string text = TranslationServer.Translate(graph.Choice(id)!.Text).ToString();
                AssertThat(Lines(text)).OverrideFailureMessage($"{id} in {locale}: {text}").IsLessEqual(2);
            }
        }
    }

    [TestCase]
    public void Hidden_the_toll_answers_are_still_french()
    {
        StoryGraph graph = StoryGraph.FromFiles();
        foreach (string id in new[] { "toll_true", "toll_lie" })
        {
            string key = graph.Choice(id)!.Text;
            TranslationServer.SetLocale("en");
            string english = TranslationServer.Translate(key).ToString();
            TranslationServer.SetLocale("fr");
            string french = TranslationServer.Translate(key).ToString();
            AssertThat(french).OverrideFailureMessage(id).IsNotEqual(key);
            AssertThat(french).OverrideFailureMessage(id).IsNotEqual(english);
            AssertThat(french.Length).OverrideFailureMessage(id).IsGreater(10);
        }
    }
}
