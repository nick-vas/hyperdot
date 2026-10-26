namespace SaltmereCrossing.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Every line, choice and ending title of the story has its text in every language the game ships: a key missing from
/// the tables would be shown to the player as it is.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class StoryTextTest
{
    [AfterTest]
    public void English()
    {
        TranslationServer.SetLocale("en");
    }

    private static List<string> Keys(StoryGraph graph)
    {
        var keys = new List<string>();
        foreach (string id in graph.NodeIds)
            keys.Add(graph.Node(id)!.Text);
        foreach (string id in graph.ChoiceIds)
        {
            if (!keys.Contains(graph.Choice(id)!.Text))
                keys.Add(graph.Choice(id)!.Text);
        }
        foreach (string id in graph.EndingIds)
            keys.Add(graph.Ending(id)!.Title);
        keys.AddRange(new[] { "SPEAKER_NARRATOR", "SPEAKER_STRANGER", "CHAPTER_1", "CHAPTER_2", "CHAPTER_3" });
        return keys;
    }

    [TestCase]
    public void Every_story_text_is_translated_in_every_language()
    {
        List<string> keys = Keys(StoryGraph.FromFiles());
        foreach (string locale in TranslationServer.GetLoadedLocales())
        {
            TranslationServer.SetLocale(locale);
            foreach (string key in keys)
                AssertThat(TranslationServer.Translate(key).ToString()).OverrideFailureMessage($"{key} in {locale}").IsNotEqual(key);
        }
    }
}
