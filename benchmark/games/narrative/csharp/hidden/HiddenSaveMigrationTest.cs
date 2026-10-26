namespace SaltmereCrossing.Tests;

using System;
using System.IO;
using System.Text.Json.Nodes;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the alpha's migrate-save: a version 1 save carries on its story and keeps its endings.</summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenSaveMigrationTest
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

    private SaveData Read(string text)
    {
        File.WriteAllText(_path, text);
        return new SaveStore(_path).Read();
    }

    [TestCase]
    public void Hidden_a_version_1_story_carries_on_where_it_was()
    {
        SaveData data = Read("""{"version": 1, "choices": ["dock_greet", "toll_lie", "launch_row", "fog_steady", "ask_name"], "found": ["return", "shore"]}""");
        AssertThat(data.Endings).ContainsExactly("return", "shore");
        AssertThat(data.Story).OverrideFailureMessage("a story to continue").IsNotNull();
        if (data.Story == null)
            return;
        Story story = Story.FromDict(_graph, data.Story);
        Story played = Story.Replay(_graph, new[] { "dock_greet", "toll_lie", "launch_row", "fog_steady", "ask_name" });
        AssertThat(story.NodeId).IsEqual("name");
        AssertThat(story.Flag("trust")).IsEqual(2);
        AssertThat(story.Flag("lied")).IsEqual(1);
        AssertThat(story.Flag("afraid")).IsEqual(0);
        AssertThat(story.History).ContainsExactly(played.History.ToArray());
        AssertThat(story.CanChoose("ask_name")).IsFalse();
        AssertThat(story.Choose("name_back")).IsTrue();
        AssertThat(story.CanChoose("confess")).IsTrue();
    }

    [TestCase]
    public void Hidden_a_file_without_a_version_is_version_1()
    {
        SaveData data = Read("""{"choices": ["dock_silent"], "found": ["return"]}""");
        AssertThat(data.Endings).ContainsExactly("return");
        AssertThat(data.Story).IsNotNull();
        if (data.Story != null)
            AssertThat(Story.FromDict(_graph, data.Story).NodeId).IsEqual("toll");
    }

    [TestCase]
    public void Hidden_a_version_1_save_between_stories_has_nothing_to_continue()
    {
        SaveData data = Read("""{"version": 1, "choices": [], "found": ["shore"]}""");
        AssertThat(data.Endings).ContainsExactly("shore");
        AssertThat(data.Story).IsNull();
    }

    [TestCase]
    public void Hidden_a_migrated_save_is_written_as_the_current_version()
    {
        var store = new SaveStore(_path);
        File.WriteAllText(_path, """{"version": 1, "choices": ["dock_greet"], "found": ["return"]}""");
        SaveData data = store.Read();
        SaveStore.RecordEnding(data, "shore");
        AssertThat(store.Write(data)).IsTrue();
        var raw = (JsonObject)JsonNode.Parse(File.ReadAllText(_path))!;
        AssertThat(JsonData.Int(raw["version"], 0)).IsEqual(SaveStore.Version);
        SaveData back = store.Read();
        AssertThat(back.Endings).ContainsExactly("return", "shore");
        AssertThat(back.Story).IsNotNull();
        if (back.Story != null)
            AssertThat(JsonData.Text(back.Story["node"], "")).IsEqual("toll");
    }

    [TestCase]
    public void Hidden_a_version_2_save_is_read_as_it_is()
    {
        SaveData data = Read("""{"version": 2, "story": {"node": "fog", "flags": {"trust": 1, "lied": 0, "afraid": 1}, "history": ["dock_greet", "toll_lie", "launch_row"]}, "endings": ["shore"], "settings": {"volume": 0.5, "locale": "en"}}""");
        AssertThat(data.Endings).ContainsExactly("shore");
        AssertThat(JsonData.Text(data.Story?["node"], "")).IsEqual("fog");
        AssertThat(data.Volume).IsEqualApprox(0.5, 0.001);
    }
}
