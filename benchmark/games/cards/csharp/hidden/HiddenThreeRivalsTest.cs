namespace Lanternfen.Tests;

using System;
using System.IO;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden acceptance for the alpha milestone: three rivals with legal decks, and a save that keeps the record and the
/// duel in progress, discard piles included.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenThreeRivalsTest
{
    private string _path = "";
    private Cards _cards = null!;
    private Rivals _rivals = null!;

    [BeforeTest]
    public void Load()
    {
        _path = Path.Combine(Path.GetTempPath(), $"lanternfen-hidden-three-{Guid.NewGuid():N}.json");
        _cards = Cards.FromFile();
        _rivals = Rivals.FromFiles();
    }

    [AfterTest]
    public void RemoveFile()
    {
        File.Delete(_path);
    }

    [TestCase]
    public void Hidden_three_rivals_with_legal_decks()
    {
        AssertThat(_rivals.Count).IsGreaterEqual(3);
        foreach (int id in new[] { 1, 2, 3 })
        {
            AssertThat(_rivals.HasRival(id)).OverrideFailureMessage($"rival {id}").IsTrue();
            var problems = Deck.Problems(_rivals.DeckOf(_rivals.Rival(id)!.Deck), _cards);
            AssertThat(problems).OverrideFailureMessage($"rival {id}: {string.Join(", ", problems)}").IsEmpty();
            int winner = Ai.PlayOut(_rivals.StartDuel(_cards, id, 4), new[] { new Ai(), _rivals.AiFor(id) });
            AssertThat(winner == 0 || winner == 1).OverrideFailureMessage($"rival {id}'s duel ends").IsTrue();
        }
    }

    [TestCase]
    public void Hidden_the_save_keeps_the_record_and_the_duel()
    {
        Duel duel = _rivals.StartDuel(_cards, 3, 8);
        duel.Advance();
        duel.Keepers[0].Discard = new System.Collections.Generic.List<string> { "glow_imp", "flare" };
        var store = new SaveStore(_path);
        SaveData data = store.Read();
        data.Record["1"] = new RivalRecord { Wins = 1, Losses = 2 };
        data.Duel = duel.ToDict();
        AssertThat(store.Write(data)).IsTrue();
        SaveData back = new SaveStore(_path).Read();
        AssertThat(back.Record["1"].Wins).IsEqual(1);
        AssertThat(back.Record["1"].Losses).IsEqual(2);
        Duel restored = Duel.FromDict(_cards, back.Duel!);
        AssertThat(restored.Turn).IsEqual(duel.Turn);
        AssertThat(restored.Keepers[0].Hand).ContainsExactly(duel.Keepers[0].Hand);
        AssertThat(restored.Keepers[0].Discard).ContainsExactly(duel.Keepers[0].Discard);
        AssertThat(restored.Keepers[1].Deck).ContainsExactly(duel.Keepers[1].Deck);
    }
}
