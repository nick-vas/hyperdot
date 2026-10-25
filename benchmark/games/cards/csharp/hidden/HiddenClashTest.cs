namespace Lanternfen.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the prototype's fix-bug: Main goes to Clash whenever the active keeper has a wisp, whatever the
/// other row holds, and skips it when the active keeper has none, whatever the other row holds.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenClashTest
{
    private Cards _cards = null!;
    private Duel _duel = null!;

    [BeforeTest]
    public void Deal()
    {
        _cards = Cards.FromFile();
        var deck = Rivals.FromFiles().DeckOf(Rivals.KeeperDeck);
        _duel = Duel.Start(_cards, new[] { deck, deck }, new[] { 20, 20 }, 3);
        _duel.Advance();
    }

    private Wisp WispOf(string id) => Wisp.Of(_cards.Get(id));

    [TestCase]
    public void Hidden_wisps_strike_a_rival_whose_row_is_empty()
    {
        _duel.Keepers[0].Row[0] = WispOf("reed_hound");
        _duel.Keepers[0].Row[2] = WispOf("glow_imp");
        _duel.EndMain();
        AssertThat(_duel.Phase).IsEqual(Phase.Clash);
        _duel.Advance();
        _duel.Advance();
        AssertThat(_duel.Keepers[1].Light).IsEqual(15);
        _duel.Advance();
        AssertThat(_duel.Phase).IsEqual(Phase.End);
    }

    [TestCase]
    public void Hidden_the_rivals_wisps_strike_an_empty_row_too()
    {
        _duel.EndMain();
        _duel.Advance();
        _duel.Advance();
        AssertThat(_duel.Active).IsEqual(1);
        AssertThat(_duel.Phase).IsEqual(Phase.Main);
        _duel.Keepers[1].Row[1] = WispOf("fen_stalker");
        _duel.EndMain();
        AssertThat(_duel.Phase).IsEqual(Phase.Clash);
        _duel.Advance();
        AssertThat(_duel.Keepers[0].Light).IsEqual(16);
    }

    [TestCase]
    public void Hidden_no_wisp_of_ones_own_skips_the_clash_even_facing_wisps()
    {
        _duel.Keepers[1].Row[0] = WispOf("bog_warden");
        _duel.EndMain();
        AssertThat(_duel.Phase).IsEqual(Phase.End);
        AssertThat(_duel.Keepers[1].Row[0]!.Guard).IsEqual(6);
    }
}
