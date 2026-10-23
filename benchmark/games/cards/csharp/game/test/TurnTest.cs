namespace Lanternfen.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// A turn as named phases, one test per transition: Draw -> Main -> Clash (or End when there is nothing to strike
/// with) -> End -> the other keeper's Draw, and Over once a light is out.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class TurnTest
{
    private Cards _cards = null!;
    private Duel _duel = null!;

    [BeforeTest]
    public void Deal()
    {
        _cards = Cards.FromFile();
        var deck = Rivals.FromFiles().DeckOf(Rivals.KeeperDeck);
        _duel = Duel.Start(_cards, new[] { deck, deck }, new[] { 20, 20 }, 7);
    }

    private Wisp WispOf(string id) => Wisp.Of(_cards.Get(id));

    [TestCase]
    public void A_duel_opens_on_the_first_keepers_draw()
    {
        AssertThat(_duel.Phase).IsEqual(Phase.Draw);
        AssertThat(_duel.Active).IsEqual(0);
        AssertThat(_duel.Turn).IsEqual(1);
        AssertThat(_duel.Keepers[0].Hand.Count).IsEqual(Duel.HandStart);
        AssertThat(_duel.Keepers[1].Hand.Count).IsEqual(Duel.HandStart);
    }

    [TestCase]
    public void Draw_gives_kindling_and_a_card_then_main()
    {
        _duel.Advance();
        AssertThat(_duel.Phase).IsEqual(Phase.Main);
        AssertThat(_duel.Keepers[0].Kindling).IsEqual(1);
        AssertThat(_duel.Keepers[0].Hand.Count).IsEqual(Duel.HandStart + 1);
    }

    [TestCase]
    public void Main_goes_to_clash_when_the_keeper_has_wisps()
    {
        _duel.Advance();
        _duel.Keepers[0].Row[0] = WispOf("reed_hound");
        _duel.Keepers[1].Row[0] = WispOf("bog_warden");
        _duel.EndMain();
        AssertThat(_duel.Phase).IsEqual(Phase.Clash);
    }

    [TestCase]
    public void Main_skips_clash_when_no_wisp_can_strike()
    {
        _duel.Advance();
        _duel.EndMain();
        AssertThat(_duel.Phase).IsEqual(Phase.End);
    }

    [TestCase]
    public void Clash_strikes_each_lane_then_ends()
    {
        _duel.Advance();
        _duel.Keepers[0].Row = new[] { WispOf("reed_hound"), null, WispOf("glow_imp") };
        _duel.Keepers[1].Row = new[] { WispOf("bog_warden"), null, null };
        _duel.EndMain();
        _duel.Advance();
        AssertThat(_duel.Keepers[1].Row[0]!.Guard).OverrideFailureMessage("lane 0 struck the warden").IsEqual(4);
        AssertThat(_duel.Phase).IsEqual(Phase.Clash);
        _duel.Advance();
        AssertThat(_duel.Keepers[1].Light).OverrideFailureMessage("lane 2 struck the rival").IsEqual(17);
        _duel.Advance();
        AssertThat(_duel.Phase).IsEqual(Phase.End);
    }

    [TestCase]
    public void End_passes_the_turn_to_the_other_keeper()
    {
        _duel.Advance();
        _duel.EndMain();
        _duel.Advance();
        AssertThat(_duel.Phase).IsEqual(Phase.Draw);
        AssertThat(_duel.Active).IsEqual(1);
        AssertThat(_duel.Turn).IsEqual(2);
    }

    [TestCase]
    public void A_light_put_out_ends_the_duel()
    {
        _duel.Advance();
        _duel.Keepers[0].Row[1] = WispOf("lantern_heron");
        _duel.Keepers[1].Row[0] = WispOf("bog_warden");
        _duel.Keepers[1].Light = 4;
        _duel.EndMain();
        _duel.Advance();
        AssertThat(_duel.Phase).IsEqual(Phase.Over);
        AssertThat(_duel.Winner).IsEqual(0);
        _duel.Advance();
        AssertThat(_duel.Phase).OverrideFailureMessage("nothing moves an ended duel").IsEqual(Phase.Over);
    }
}
