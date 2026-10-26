namespace SaltmereCrossing.Tests;

using System;
using System.IO;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden acceptance for the prototype-to-alpha milestone: the story saved with its flags and history, once-only
/// questions, and a story check that is clean for the game and finds a broken story.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenAlphaTest
{
    private string _path = "";
    private StoryGraph _graph = null!;

    [BeforeTest]
    public void Prepare()
    {
        _path = Path.Combine(Path.GetTempPath(), $"saltmere-hidden-{Guid.NewGuid():N}.json");
        _graph = StoryGraph.FromFiles();
    }

    [AfterTest]
    public void RemoveFile()
    {
        File.Delete(_path);
    }

    [TestCase]
    public void Hidden_a_story_comes_back_through_the_save()
    {
        Story story = Story.Replay(_graph, new[] { "dock_greet", "toll_lie", "launch_row", "fog_steady", "ask_name" });
        var store = new SaveStore(_path);
        var data = new SaveData { Story = story.ToDict() };
        data.Endings.Add("return");
        AssertThat(store.Write(data)).IsTrue();
        SaveData read = store.Read();
        AssertThat(read.Endings).ContainsExactly("return");
        Story back = Story.FromDict(_graph, read.Story!);
        AssertThat(back.NodeId).IsEqual("name");
        AssertThat(back.Flag("trust")).IsEqual(2);
        AssertThat(back.Flag("lied")).IsEqual(1);
        AssertThat(back.History).ContainsExactly(story.History.ToArray());
    }

    [TestCase]
    public void Hidden_the_questions_are_asked_once()
    {
        Story story = Story.Replay(_graph, new[] { "dock_silent", "toll_true", "launch_row", "fog_hurry", "ask_name", "name_back", "ask_cargo", "cargo_back" });
        AssertThat(story.NodeId).IsEqual("crossing");
        AssertThat(story.CanChoose("ask_name")).IsFalse();
        AssertThat(story.CanChoose("ask_cargo")).IsFalse();
        AssertThat(story.CanChoose("cross_on")).IsTrue();
    }

    [TestCase]
    public void Hidden_the_story_check_is_clean_for_the_game()
    {
        AssertThat(StoryCheck.Problems(_graph)).IsEmpty();
    }

    [TestCase]
    public void Hidden_the_story_check_finds_a_broken_story()
    {
        StoryGraph broken = StoryGraph.FromJson(
            """[{"id": "a"}, {"id": "lost"}, {"id": "end"}]""",
            """
            [{"id": "go", "from": "a", "to": "nowhere"}, {"id": "on", "from": "a", "to": "end", "set": ["kept"]},
             {"id": "out", "from": "lost", "to": "end"}]
            """,
            """[{"id": "kept", "kind": "switch"}]""",
            """[{"id": "end", "node": "end"}]""");
        string text = string.Join("\n", StoryCheck.Problems(broken));
        foreach (string word in new[] { "nowhere", "lost", "kept" })
            AssertThat(text).Contains(word);
    }
}
