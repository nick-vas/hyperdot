namespace SaltmereCrossing.Tests;

using System.Collections.Generic;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>StoryCheck on the game's story, and on small broken ones: what the data runner cannot see.</summary>
[TestSuite]
[RequireGodotRuntime]
public class StoryCheckTest
{
    private const string OneEnding = """[{"id": "end", "node": "end"}]""";

    private StoryGraph _graph = null!;

    [BeforeTest]
    public void Load()
    {
        _graph = StoryGraph.FromFiles();
    }

    [TestCase]
    public void The_story_has_no_problems()
    {
        AssertThat(StoryCheck.Problems(_graph)).IsEmpty();
    }

    [TestCase]
    public void Every_ending_can_be_reached()
    {
        StorySearch found = StoryCheck.Search(_graph);
        foreach (string id in _graph.EndingIds)
            AssertThat(found.Endings.Contains(id)).OverrideFailureMessage(id).IsTrue();
        AssertThat(found.Nodes.Count).IsEqual(_graph.NodeIds.Count);
    }

    [TestCase]
    public void The_way_to_each_ending_is_offered_choice_by_choice()
    {
        foreach (string id in _graph.EndingIds)
        {
            var story = new Story(_graph);
            foreach (string choice in StoryCheck.PathTo(_graph, id))
                AssertThat(story.Choose(choice)).OverrideFailureMessage($"{choice} on the way to {id}").IsTrue();
            AssertThat(story.Ending()).IsEqual(id);
        }
    }

    [TestCase]
    public void A_choice_to_a_missing_node_is_found()
    {
        StoryGraph broken = StoryGraph.FromJson(
            """[{"id": "a"}, {"id": "end"}]""",
            """[{"id": "go", "from": "a", "to": "ned"}, {"id": "on", "from": "a", "to": "end"}]""",
            "[]", OneEnding);
        AssertThat(StoryCheck.Problems(broken)).Contains("choice 'go' leads to 'ned', which is no node");
    }

    [TestCase]
    public void A_node_nobody_reaches_is_found()
    {
        StoryGraph broken = StoryGraph.FromJson(
            """[{"id": "a"}, {"id": "lost"}, {"id": "end"}]""",
            """[{"id": "on", "from": "a", "to": "end"}, {"id": "out", "from": "lost", "to": "end"}]""",
            "[]", OneEnding);
        AssertThat(StoryCheck.Problems(broken)).Contains("node 'lost' cannot be reached");
    }

    [TestCase]
    public void Flags_set_and_never_read_or_read_and_never_set_are_found()
    {
        StoryGraph broken = StoryGraph.FromJson(
            """[{"id": "a"}, {"id": "end"}]""",
            """[{"id": "on", "from": "a", "to": "end", "needs": "!ghost", "set": ["kept"]}]""",
            """[{"id": "kept", "kind": "switch"}]""", OneEnding);
        List<string> problems = StoryCheck.Problems(broken);
        AssertThat(problems).Contains("flag 'kept' is never read");
        AssertThat(problems).Contains("flag 'ghost' of choice 'on' is not in flags.json");
    }

    [TestCase]
    public void An_ending_a_flag_locks_away_is_found()
    {
        StoryGraph broken = StoryGraph.FromJson(
            """[{"id": "a"}, {"id": "b"}, {"id": "end"}, {"id": "other"}]""",
            """
            [{"id": "scare", "from": "a", "to": "b", "set": ["afraid"]},
             {"id": "calm", "from": "b", "to": "b", "needs": "afraid=1"},
             {"id": "land", "from": "b", "to": "end", "needs": "!afraid"},
             {"id": "flee", "from": "b", "to": "other"}]
            """,
            """[{"id": "afraid", "kind": "switch"}]""",
            """[{"id": "end", "node": "end"}, {"id": "other", "node": "other"}]""");
        AssertThat(StoryCheck.Problems(broken)).Contains("ending 'end' cannot be reached");
    }

    [TestCase]
    public void A_story_that_can_get_stuck_is_found()
    {
        StoryGraph broken = StoryGraph.FromJson(
            """[{"id": "a"}, {"id": "b"}, {"id": "end"}]""",
            """
            [{"id": "lie", "from": "a", "to": "b", "set": ["lied"]}, {"id": "truth", "from": "a", "to": "b"},
             {"id": "on", "from": "b", "to": "end", "needs": "!lied"}]
            """,
            """[{"id": "lied", "kind": "switch"}]""", OneEnding);
        AssertThat(string.Join("\n", StoryCheck.Problems(broken))).Contains("a story can get stuck at 'b'");
    }
}
