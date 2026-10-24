namespace Lanternfen.Tests;

using System.Collections.Generic;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Ai: it plays only what the rules allow, passes when nothing is worth it, and its weights show in its choices.</summary>
[TestSuite]
[RequireGodotRuntime]
public class AiTest
{
    private Rivals _rivals = null!;
    private Cards _cards = null!;
    private Duel _duel = null!;

    [BeforeTest]
    public void Deal()
    {
        _cards = Cards.FromFile();
        _rivals = Rivals.FromFiles();
        _duel = _rivals.StartDuel(_cards, 1, 9);
        _duel.Advance();
    }

    private void SetHand(int kindling, params string[] hand)
    {
        _duel.Keepers[0].Hand = new List<string>(hand);
        _duel.Keepers[0].Kindling = kindling;
    }

    [TestCase]
    public void The_ai_only_chooses_cards_it_can_pay_for()
    {
        SetHand(2, "lantern_heron", "fen_stalker", "ember_mote");
        AssertThat(new Ai().Choose(_duel, 0)).IsEqual(2);
    }

    [TestCase]
    public void The_ai_passes_when_nothing_can_be_played()
    {
        SetHand(4, "lantern_heron", "douse");
        AssertThat(new Ai().Choose(_duel, 0)).OverrideFailureMessage("a heron it cannot pay for, nothing to douse").IsEqual(-1);
    }

    [TestCase]
    public void The_ai_takes_a_winning_flare()
    {
        SetHand(6, "lantern_heron", "flare");
        _duel.Keepers[1].Light = 3;
        AssertThat(new Ai().Choose(_duel, 0)).IsEqual(1);
    }

    [TestCase]
    public void The_ai_never_mends_at_full_light_and_mends_when_low()
    {
        SetHand(2, "mending_oil");
        AssertThat(new Ai().Choose(_duel, 0)).IsEqual(-1);
        _duel.Keepers[0].Light = 6;
        AssertThat(new Ai().Choose(_duel, 0)).IsEqual(0);
    }

    [TestCase]
    public void Caution_values_a_wall_more_than_aggression_does()
    {
        SetHand(3, "bog_warden");
        AssertThat(new Ai(0.5, 2.0).Score(_duel, 0, 0)).IsGreater(new Ai(2.0, 0.5).Score(_duel, 0, 0));
    }

    [TestCase]
    public void Two_ais_play_a_duel_to_its_end()
    {
        int winner = Ai.PlayOut(_rivals.StartDuel(_cards, 1, 3), new[] { new Ai(), _rivals.AiFor(1) });
        AssertThat(winner == 0 || winner == 1).OverrideFailureMessage($"winner {winner}").IsTrue();
    }
}
