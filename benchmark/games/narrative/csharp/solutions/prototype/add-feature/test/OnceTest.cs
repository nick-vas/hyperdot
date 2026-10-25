namespace SaltmereCrossing.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Once-only choices: the questions at the crossing are asked once per story.</summary>
[TestSuite]
[RequireGodotRuntime]
public class OnceTest
{
    private StoryGraph _graph = null!;

    [BeforeTest]
    public void Load()
    {
        _graph = StoryGraph.FromFiles();
    }

    private Story AtCrossing() => Story.Replay(_graph, new[] { "dock_silent", "toll_true", "launch_row", "fog_hurry" });

    [TestCase]
    public void A_question_asked_is_not_offered_again()
    {
        Story story = AtCrossing();
        AssertThat(story.CanChoose("ask_name")).IsTrue();
        AssertThat(story.Choose("ask_name")).IsTrue();
        AssertThat(story.Choose("name_back")).IsTrue();
        AssertThat(story.NodeId).IsEqual("crossing");
        AssertThat(story.CanChoose("ask_name")).IsFalse();
        AssertThat(story.CanChoose("ask_cargo")).OverrideFailureMessage("the other questions stay").IsTrue();
    }

    [TestCase]
    public void Trust_cannot_be_won_by_asking_twice()
    {
        Story story = AtCrossing();
        story.Choose("ask_name");
        story.Choose("name_back");
        AssertThat(story.Choose("ask_name")).IsFalse();
        AssertThat(story.Flags["trust"]).IsEqual(2);
    }

    [TestCase]
    public void A_new_story_asks_again()
    {
        Story story = AtCrossing();
        story.Choose("ask_name");
        AssertThat(AtCrossing().CanChoose("ask_name")).IsTrue();
    }

    [TestCase]
    public void A_story_carried_on_remembers_what_was_asked()
    {
        Story story = AtCrossing();
        story.Choose("ask_name");
        story.Choose("name_back");
        Story back = Story.FromDict(_graph, story.ToDict());
        AssertThat(back.CanChoose("ask_name")).IsFalse();
    }
}
