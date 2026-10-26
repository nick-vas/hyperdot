namespace Lanternfen.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the prototype's add-feature: fatigue costs 1, 2, 3... light per draw from an empty deck, counted in
/// Keeper.Fatigue for each keeper apart, and can end the duel at the Draw.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenFatigueTest
{
    private Duel _duel = null!;

    [BeforeTest]
    public void Deal()
    {
        var deck = Rivals.FromFiles().DeckOf(Rivals.KeeperDeck);
        _duel = Duel.Start(Cards.FromFile(), new[] { deck, deck }, new[] { 20, 20 }, 5);
    }

    [TestCase]
    public void Hidden_each_empty_draw_costs_one_more()
    {
        _duel.Keepers[0].Deck.Clear();
        int hand = _duel.Keepers[0].Hand.Count;
        foreach (int expected in new[] { 19, 17, 14, 10 })
        {
            AssertThat(_duel.DrawCard(0)).IsFalse();
            AssertThat(_duel.Keepers[0].Light).IsEqual(expected);
        }
        AssertThat(_duel.Keepers[0].Fatigue).IsEqual(4);
        AssertThat(_duel.Keepers[0].Hand.Count).IsEqual(hand);
    }

    [TestCase]
    public void Hidden_fatigue_is_counted_per_keeper()
    {
        _duel.Keepers[0].Deck.Clear();
        _duel.Keepers[1].Deck.Clear();
        _duel.DrawCard(0);
        _duel.DrawCard(0);
        _duel.DrawCard(1);
        AssertThat(_duel.Keepers[0].Fatigue).IsEqual(2);
        AssertThat(_duel.Keepers[1].Fatigue).IsEqual(1);
        AssertThat(_duel.Keepers[1].Light).IsEqual(19);
    }

    [TestCase]
    public void Hidden_a_deck_with_cards_costs_nothing()
    {
        _duel.DrawCard(0);
        AssertThat(_duel.Keepers[0].Light).IsEqual(20);
        AssertThat(_duel.Keepers[0].Fatigue).IsEqual(0);
    }

    [TestCase]
    public void Hidden_fatigue_ends_the_duel_at_the_draw()
    {
        _duel.Keepers[0].Deck.Clear();
        _duel.Keepers[0].Fatigue = 2;
        _duel.Keepers[0].Light = 3;
        _duel.Advance();
        AssertThat(_duel.Keepers[0].Light).IsEqual(0);
        AssertThat(_duel.Phase).IsEqual(Phase.Over);
        AssertThat(_duel.Winner).IsEqual(1);
    }
}
