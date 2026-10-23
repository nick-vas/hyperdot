namespace Lanternfen.Tests;

using System.Collections.Generic;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Duel: what each rite does when played, once.</summary>
[TestSuite]
[RequireGodotRuntime]
public class DuelTest
{
    private Cards _cards = null!;

    [BeforeTest]
    public void Load()
    {
        _cards = Cards.FromFile();
    }

    [TestCase]
    public void Flare_burns_the_rival_for_three()
    {
        Duel duel = AtMain("flare");
        AssertThat(duel.Play(0, 0)).IsTrue();
        AssertThat(duel.Keepers[1].Light).IsEqual(17);
    }

    [TestCase]
    public void Mending_oil_restores_light_up_to_the_start()
    {
        Duel duel = AtMain("mending_oil", "mending_oil");
        duel.Keepers[0].Light = 14;
        duel.Play(0, 0);
        AssertThat(duel.Keepers[0].Light).IsEqual(18);
        duel.Play(0, 0);
        AssertThat(duel.Keepers[0].Light).IsEqual(20);
    }

    [TestCase]
    public void Marsh_insight_draws_two()
    {
        Duel duel = AtMain("marsh_insight");
        int deckBefore = duel.Keepers[0].Deck.Count;
        duel.Play(0, 0);
        AssertThat(duel.Keepers[0].Hand.Count).IsEqual(2);
        AssertThat(duel.Keepers[0].Deck.Count).IsEqual(deckBefore - 2);
    }

    [TestCase]
    public void Douse_puts_out_the_strongest_wisp_across()
    {
        Duel duel = AtMain("douse");
        duel.Keepers[1].Row = new Wisp?[] { new("reed_hound", 2, 3), new("fen_stalker", 4, 3), null };
        duel.Play(0, 0);
        AssertThat(duel.Keepers[1].Row[1]).IsNull();
        AssertThat(duel.Keepers[1].Row[0]).IsNotNull();
        AssertThat(duel.Keepers[1].Discard).ContainsExactly("fen_stalker");
    }

    [TestCase]
    public void Rekindle_returns_the_newest_fallen_wisp()
    {
        Duel duel = AtMain("rekindle");
        duel.Keepers[0].Discard = new List<string> { "glow_imp", "flare", "reed_hound", "mending_oil" };
        duel.Play(0, 0);
        AssertThat(duel.Keepers[0].Hand).ContainsExactly("reed_hound");
        AssertThat(duel.Keepers[0].Discard).ContainsExactly("glow_imp", "flare", "mending_oil", "rekindle");
    }

    [TestCase]
    public void A_rite_with_nothing_to_act_on_cannot_be_played()
    {
        Duel duel = AtMain("douse", "rekindle");
        AssertThat(duel.CanPlay(0, 0)).OverrideFailureMessage("douse with no wisp across").IsFalse();
        AssertThat(duel.CanPlay(0, 1)).OverrideFailureMessage("rekindle with no fallen wisp").IsFalse();
        AssertThat(duel.Play(0, 0)).IsFalse();
        AssertThat(duel.Keepers[0].Hand.Count).IsEqual(2);
    }

    private Duel AtMain(params string[] hand)
    {
        var deck = Rivals.FromFiles().DeckOf(Rivals.KeeperDeck);
        var duel = Duel.Start(_cards, new[] { deck, deck }, new[] { 20, 20 }, 7);
        duel.Keepers[0].Hand = new List<string>(hand);
        duel.Keepers[0].Kindling = 6;
        duel.Phase = Phase.Main;
        return duel;
    }
}
