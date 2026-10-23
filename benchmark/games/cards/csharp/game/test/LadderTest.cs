namespace Lanternfen.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Ladder: wins and losses per rival, and which rivals are open.</summary>
[TestSuite]
public class LadderTest
{
    [TestCase]
    public void Rival_one_is_open_and_the_next_opens_when_it_is_beaten()
    {
        var save = new SaveData();
        AssertThat(Ladder.IsUnlocked(save, 1)).IsTrue();
        AssertThat(Ladder.IsUnlocked(save, 2)).IsFalse();
        Ladder.Record(save, 1, true);
        AssertThat(Ladder.IsUnlocked(save, 2)).IsTrue();
        AssertThat(Ladder.IsUnlocked(save, 3)).IsFalse();
    }

    [TestCase]
    public void A_loss_opens_nothing_and_is_counted()
    {
        var save = new SaveData();
        Ladder.Record(save, 1, false);
        Ladder.Record(save, 1, false);
        AssertThat(Ladder.IsBeaten(save, 1)).IsFalse();
        AssertThat(Ladder.Losses(save, 1)).IsEqual(2);
        AssertThat(Ladder.IsUnlocked(save, 2)).IsFalse();
    }

    [TestCase]
    public void Wins_add_up_across_rivals()
    {
        var save = new SaveData();
        Ladder.Record(save, 1, true);
        Ladder.Record(save, 1, true);
        Ladder.Record(save, 2, true);
        Ladder.Record(save, 3, false);
        AssertThat(Ladder.Wins(save, 1)).IsEqual(2);
        AssertThat(Ladder.TotalWins(save)).IsEqual(3);
    }
}
