namespace Lanternfen.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Fatigue: an empty deck costs light, more each time, so every duel ends.</summary>
[TestSuite]
[RequireGodotRuntime]
public class FatigueTest
{
    private Duel _duel = null!;

    [BeforeTest]
    public void Deal()
    {
        var deck = Rivals.FromFiles().DeckOf(Rivals.KeeperDeck);
        _duel = Duel.Start(Cards.FromFile(), new[] { deck, deck }, new[] { 20, 20 }, 5);
        _duel.Keepers[0].Deck.Clear();
    }

    [TestCase]
    public void Each_draw_from_an_empty_deck_costs_one_more_light()
    {
        AssertThat(_duel.DrawCard(0)).IsFalse();
        AssertThat(_duel.Keepers[0].Light).IsEqual(19);
        _duel.DrawCard(0);
        _duel.DrawCard(0);
        AssertThat(_duel.Keepers[0].Light).IsEqual(14);
        AssertThat(_duel.Keepers[0].Fatigue).IsEqual(3);
        AssertThat(_duel.Keepers[0].Hand.Count).IsEqual(Duel.HandStart);
    }

    [TestCase]
    public void Fatigue_can_put_out_a_light_at_the_draw()
    {
        _duel.Keepers[0].Light = 1;
        _duel.Advance();
        AssertThat(_duel.Phase).IsEqual(Phase.Over);
        AssertThat(_duel.Winner).IsEqual(1);
    }
}
