namespace Lanternfen.Tests;

using System;
using System.IO;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>A duel kept in the save comes back as it was, so Continue carries on where the player stopped.</summary>
[TestSuite]
[RequireGodotRuntime]
public class DuelSaveTest
{
    private string _path = "";
    private Cards _cards = null!;
    private Rivals _rivals = null!;

    [BeforeTest]
    public void Load()
    {
        _path = Path.Combine(Path.GetTempPath(), $"lanternfen-duel-{Guid.NewGuid():N}.json");
        _cards = Cards.FromFile();
        _rivals = Rivals.FromFiles();
    }

    [AfterTest]
    public void RemoveFile()
    {
        File.Delete(_path);
    }

    /// <summary>A duel played by two AIs up to the player's Main phase of turn 7.</summary>
    private Duel DuelInPlay()
    {
        Duel duel = _rivals.StartDuel(_cards, 2, 21);
        var ais = new[] { new Ai(), _rivals.AiFor(2) };
        while (!(duel.Turn == 7 && duel.Phase == Phase.Main))
        {
            if (duel.Phase == Phase.Main)
            {
                int index = ais[duel.Active].Choose(duel, duel.Active);
                if (index < 0 || !duel.Play(duel.Active, index))
                    duel.EndMain();
            }
            else
            {
                duel.Advance();
            }
        }
        return duel;
    }

    [TestCase]
    public void A_saved_duel_comes_back_with_its_hands_decks_rows_and_light()
    {
        Duel duel = DuelInPlay();
        var store = new SaveStore(_path);
        var data = new SaveData { Duel = duel.ToDict() };
        AssertThat(store.Write(data)).IsTrue();
        Duel back = Duel.FromDict(_cards, store.Read().Duel!);
        AssertThat(back.Turn).IsEqual(7);
        AssertThat(back.Phase).IsEqual(Phase.Main);
        AssertThat(back.Active).IsEqual(0);
        for (int seat = 0; seat < 2; seat++)
        {
            AssertThat(back.Keepers[seat].Light).OverrideFailureMessage($"seat {seat} light").IsEqual(duel.Keepers[seat].Light);
            AssertThat(back.Keepers[seat].Kindling).OverrideFailureMessage($"seat {seat} kindling").IsEqual(duel.Keepers[seat].Kindling);
            AssertThat(back.Keepers[seat].Hand).OverrideFailureMessage($"seat {seat} hand").ContainsExactly(duel.Keepers[seat].Hand);
            AssertThat(back.Keepers[seat].Deck).OverrideFailureMessage($"seat {seat} deck").ContainsExactly(duel.Keepers[seat].Deck);
            AssertThat(back.Keepers[seat].Row).OverrideFailureMessage($"seat {seat} row").ContainsExactly(duel.Keepers[seat].Row);
        }
    }

    [TestCase]
    public void A_restored_duel_plays_on_to_its_end()
    {
        Duel back = Duel.FromDict(_cards, DuelInPlay().ToDict());
        int winner = Ai.PlayOut(back, new[] { new Ai(), _rivals.AiFor(2) });
        AssertThat(winner == 0 || winner == 1).OverrideFailureMessage($"winner {winner}").IsTrue();
    }
}
