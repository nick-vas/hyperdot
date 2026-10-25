namespace Lanternfen.Tests;

using System;
using System.Collections.Generic;
using System.IO;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the alpha's fix-bug: a duel kept in the save comes back with both discard piles, in order, so
/// Rekindle after Continue brings back the wisp that fell last.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenDiscardTest
{
    private string _path = "";
    private Cards _cards = null!;
    private Rivals _rivals = null!;

    [BeforeTest]
    public void Load()
    {
        _path = Path.Combine(Path.GetTempPath(), $"lanternfen-hidden-discard-{Guid.NewGuid():N}.json");
        _cards = Cards.FromFile();
        _rivals = Rivals.FromFiles();
    }

    [AfterTest]
    public void RemoveFile()
    {
        File.Delete(_path);
    }

    private Duel ThroughTheSave(Duel duel)
    {
        var store = new SaveStore(_path);
        AssertThat(store.Write(new SaveData { Duel = duel.ToDict() })).IsTrue();
        return Duel.FromDict(_cards, store.Read().Duel!);
    }

    private Duel DuelAtMain()
    {
        Duel duel = _rivals.StartDuel(_cards, 2, 13);
        duel.Advance();
        return duel;
    }

    [TestCase]
    public void Hidden_both_discard_piles_come_back_in_order()
    {
        Duel duel = DuelAtMain();
        duel.Keepers[0].Discard = new List<string> { "reed_hound", "flare", "glow_imp", "mending_oil" };
        duel.Keepers[1].Discard = new List<string> { "marsh_insight", "bog_warden" };
        Duel back = ThroughTheSave(duel);
        AssertThat(back.Keepers[0].Discard).ContainsExactly(duel.Keepers[0].Discard);
        AssertThat(back.Keepers[1].Discard).ContainsExactly(duel.Keepers[1].Discard);
    }

    [TestCase]
    public void Hidden_rekindle_after_continue_brings_back_the_last_fallen_wisp()
    {
        Duel duel = DuelAtMain();
        duel.Keepers[0].Hand = new List<string> { "rekindle" };
        duel.Keepers[0].Kindling = 2;
        duel.Keepers[0].Discard = new List<string> { "reed_hound", "glow_imp", "flare" };
        Duel back = ThroughTheSave(duel);
        AssertThat(back.Play(0, 0)).IsTrue();
        AssertThat(back.Keepers[0].Hand).ContainsExactly("glow_imp");
        AssertThat(back.Keepers[0].Discard).ContainsExactly("reed_hound", "flare", "rekindle");
    }

    [TestCase]
    public void Hidden_a_duel_played_on_keeps_its_discards_through_the_save()
    {
        Duel duel = _rivals.StartDuel(_cards, 2, 21);
        var ais = new[] { new Ai(), _rivals.AiFor(2) };
        while (duel.Turn < 9 && duel.Phase != Phase.Over)
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
        AssertThat(duel.Keepers[0].Discard.Count + duel.Keepers[1].Discard.Count).OverrideFailureMessage("cards were played").IsGreater(0);
        Duel back = ThroughTheSave(duel);
        for (int seat = 0; seat < 2; seat++)
            AssertThat(back.Keepers[seat].Discard).OverrideFailureMessage($"seat {seat}").ContainsExactly(duel.Keepers[seat].Discard);
    }
}
