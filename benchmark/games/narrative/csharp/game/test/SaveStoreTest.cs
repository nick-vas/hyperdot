namespace SaltmereCrossing.Tests;

using System;
using System.IO;
using System.Text.Json.Nodes;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>SaveStore: reading, writing and the move from version 1.</summary>
[TestSuite]
[RequireGodotRuntime]
public class SaveStoreTest
{
    private string _path = "";

    [BeforeTest]
    public void MakePath()
    {
        _path = Path.Combine(Path.GetTempPath(), $"saltmere-{Guid.NewGuid():N}.json");
    }

    [AfterTest]
    public void RemoveFile()
    {
        File.Delete(_path);
    }

    [TestCase]
    public void No_file_gives_the_defaults()
    {
        SaveData data = new SaveStore(_path).Read();
        AssertThat(data.Story).IsNull();
        AssertThat(data.Endings).IsEmpty();
        AssertThat(data.Locale).IsEqual("en");
    }

    [TestCase]
    public void What_is_written_reads_back()
    {
        var store = new SaveStore(_path);
        var data = new SaveData { Locale = "fr" };
        SaveStore.RecordEnding(data, "return");
        SaveStore.RecordEnding(data, "return");
        data.Story = new JsonObject { ["node"] = "toll", ["flags"] = new JsonObject { ["trust"] = 1 }, ["history"] = new JsonArray("dock_greet") };
        AssertThat(store.Write(data)).IsTrue();
        SaveData back = store.Read();
        AssertThat(back.Endings).ContainsExactly("return");
        AssertThat(JsonData.Text(back.Story!["node"], "")).IsEqual("toll");
        AssertThat(back.Locale).IsEqual("fr");
        AssertThat(File.ReadAllText(_path)).Contains("\"version\": 2");
    }

    [TestCase]
    public void A_version_1_save_keeps_its_story_and_endings()
    {
        File.WriteAllText(_path, """{"version": 1, "choices": ["dock_greet", "toll_lie", "launch_row"], "found": ["return"]}""");
        SaveData data = new SaveStore(_path).Read();
        AssertThat(data.Endings).ContainsExactly("return");
        Story story = Story.FromDict(StoryGraph.FromFiles(), data.Story!);
        AssertThat(story.NodeId).IsEqual("fog");
        AssertThat(story.Flags["trust"]).IsEqual(1);
        AssertThat(story.Flags["lied"]).IsEqual(1);
    }

    [TestCase]
    public void A_disabled_store_writes_nothing()
    {
        var store = new SaveStore(_path) { Enabled = false };
        AssertThat(store.Write(new SaveData())).IsFalse();
        AssertThat(File.Exists(_path)).IsFalse();
    }

    [TestCase]
    public void A_damaged_file_gives_the_defaults()
    {
        File.WriteAllText(_path, "not json {");
        AssertThat(new SaveStore(_path).Read().Story).IsNull();
    }
}
