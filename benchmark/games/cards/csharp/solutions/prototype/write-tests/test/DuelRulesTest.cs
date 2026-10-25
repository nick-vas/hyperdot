namespace Lanternfen.Tests;

using System.Collections.Generic;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>The duel's core rules, each pinned by a test: kindling, lanes, strikes, the discard pile and the hand limit.</summary>
[TestSuite]
[RequireGodotRuntime]
public class DuelRulesTest
{
    private Cards _cards = null!;
    private Duel _duel = null!;

    [BeforeTest]
    public void Deal()
    {
        _cards = Cards.FromFile();
        var deck = Rivals.FromFiles().DeckOf(Rivals.KeeperDeck);
        _duel = Duel.Start(_cards, new[] { deck, deck }, new[] { 20, 20 }, 11);
    }

    private Wisp WispOf(string id) => Wisp.Of(_cards.Get(id));

    private void MainWith(int kindling, params string[] hand)
    {
        _duel.Advance();
        _duel.Keepers[0].Hand = new List<string>(hand);
        _duel.Keepers[0].Kindling = kindling;
    }

    [TestCase]
    public void A_card_costing_more_than_the_kindling_left_cannot_be_played()
    {
        MainWith(4, "reed_hound", "bog_warden");
        AssertThat(_duel.Play(0, 0)).IsTrue();
        AssertThat(_duel.Keepers[0].Kindling).IsEqual(2);
        AssertThat(_duel.CanPlay(0, 0)).OverrideFailureMessage("3 to pay with 2 left").IsFalse();
        AssertThat(_duel.Play(0, 0)).IsFalse();
        AssertThat(_duel.Keepers[0].Hand).ContainsExactly("bog_warden");
    }

    [TestCase]
    public void Kindling_is_the_turn_number_up_to_six()
    {
        var seen = new List<int>();
        for (int i = 0; i < 8; i++)
        {
            _duel.Advance();
            seen.Add(_duel.Keepers[_duel.Active].Kindling);
            _duel.EndMain();
            while (_duel.Phase != Phase.Draw)
                _duel.Advance();
            _duel.Advance();
            _duel.EndMain();
            while (_duel.Phase != Phase.Draw)
                _duel.Advance();
        }
        AssertThat(seen).ContainsExactly(1, 2, 3, 4, 5, 6, 6, 6);
    }

    [TestCase]
    public void A_wisp_takes_the_first_free_lane_and_none_fits_a_full_row()
    {
        MainWith(6, "ember_mote", "ember_mote", "reed_hound", "glow_imp");
        _duel.Keepers[0].Row[0] = WispOf("bog_warden");
        AssertThat(_duel.Play(0, 0)).IsTrue();
        AssertThat(_duel.Keepers[0].Row[1]!.Id).IsEqual("ember_mote");
        AssertThat(_duel.Play(0, 0)).IsTrue();
        AssertThat(_duel.Keepers[0].Row[2]!.Id).IsEqual("ember_mote");
        AssertThat(_duel.CanPlay(0, 0)).OverrideFailureMessage("the row is full").IsFalse();
        AssertThat(_duel.Play(0, 0)).IsFalse();
        AssertThat(_duel.Keepers[0].Hand.Count).IsEqual(2);
    }

    [TestCase]
    public void Wisps_across_strike_each_other()
    {
        MainWith(1);
        _duel.Keepers[0].Row[0] = WispOf("fen_stalker");
        _duel.Keepers[1].Row[0] = WispOf("bog_warden");
        _duel.EndMain();
        _duel.Advance();
        AssertThat(_duel.Keepers[1].Row[0]!.Guard).OverrideFailureMessage("the warden took 4").IsEqual(2);
        AssertThat(_duel.Keepers[0].Row[0]!.Guard).OverrideFailureMessage("the stalker took 1").IsEqual(2);
        AssertThat(_duel.Keepers[1].Light).IsEqual(20);
    }

    [TestCase]
    public void A_fallen_wisp_goes_to_the_discard_pile()
    {
        MainWith(1);
        _duel.Keepers[0].Row[1] = WispOf("glow_imp");
        _duel.Keepers[1].Row[1] = WispOf("reed_hound");
        _duel.EndMain();
        _duel.Advance();
        AssertThat(_duel.Keepers[0].Row[1]).OverrideFailureMessage("the imp fell").IsNull();
        AssertThat(_duel.Keepers[1].Row[1]).OverrideFailureMessage("the hound fell").IsNull();
        AssertThat(_duel.Keepers[0].Discard).ContainsExactly("glow_imp");
        AssertThat(_duel.Keepers[1].Discard).ContainsExactly("reed_hound");
    }

    [TestCase]
    public void An_unblocked_wisp_strikes_the_keeper()
    {
        MainWith(1);
        _duel.Keepers[0].Row[2] = WispOf("lantern_heron");
        _duel.Keepers[1].Row[0] = WispOf("bog_warden");
        _duel.EndMain();
        _duel.Advance();
        AssertThat(_duel.Keepers[1].Light).IsEqual(15);
        AssertThat(_duel.Keepers[1].Row[0]!.Guard).OverrideFailureMessage("the warden in another lane is untouched").IsEqual(6);
    }

    [TestCase]
    public void A_card_drawn_into_a_full_hand_is_discarded()
    {
        string top = _duel.Keepers[0].Deck[0];
        _duel.Keepers[0].Hand = new List<string> { "flare", "flare", "douse", "douse", "rekindle", "rekindle", "glow_imp" };
        _duel.Advance();
        AssertThat(_duel.Keepers[0].Hand.Count).IsEqual(Duel.HandMax);
        AssertThat(_duel.Keepers[0].Discard).ContainsExactly(top);
    }

    [TestCase]
    public void The_duel_ends_when_a_light_reaches_zero()
    {
        MainWith(1);
        _duel.Keepers[0].Row[0] = WispOf("glow_imp");
        _duel.Keepers[1].Light = 3;
        _duel.EndMain();
        _duel.Advance();
        AssertThat(_duel.Keepers[1].Light).IsEqual(0);
        AssertThat(_duel.Phase).IsEqual(Phase.Over);
        AssertThat(_duel.Winner).IsEqual(0);
    }
}
