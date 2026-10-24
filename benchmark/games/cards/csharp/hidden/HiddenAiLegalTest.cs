namespace Lanternfen.Tests;

using System.Collections.Generic;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-playthrough: the AI only ever chooses a play the rules allow, in every position of
/// many seeded duels against every rival, and it never plays a wisp into a full row.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenAiLegalTest
{
    private Cards _cards = null!;
    private Rivals _rivals = null!;

    [BeforeTest]
    public void Load()
    {
        _cards = Cards.FromFile();
        _rivals = Rivals.FromFiles();
    }

    [TestCase]
    public void Hidden_every_choice_is_legal_through_whole_duels()
    {
        int checkedChoices = 0;
        for (int id = 1; id <= _rivals.Count; id++)
        {
            for (int seed = 1; seed <= 8; seed++)
            {
                Duel duel = _rivals.StartDuel(_cards, id, seed);
                var ais = new[] { new Ai(), _rivals.AiFor(id) };
                for (int step = 0; step < 4000; step++)
                {
                    if (duel.Phase == Phase.Over)
                        break;
                    if (duel.Phase != Phase.Main)
                    {
                        duel.Advance();
                        continue;
                    }
                    int index = ais[duel.Active].Choose(duel, duel.Active);
                    checkedChoices += 1;
                    if (index >= 0 && !duel.CanPlay(duel.Active, index))
                    {
                        AssertThat(false).OverrideFailureMessage($"rival {id} seed {seed} turn {duel.Turn}: seat {duel.Active} chose {duel.Keepers[duel.Active].Hand[index]}, which the rules refuse").IsTrue();
                        return;
                    }
                    if (index < 0)
                        duel.EndMain();
                    else
                        duel.Play(duel.Active, index);
                }
                AssertThat(duel.Phase).OverrideFailureMessage($"rival {id} seed {seed} ended").IsEqual(Phase.Over);
            }
        }
        AssertThat(checkedChoices).IsGreater(500);
    }

    [TestCase]
    public void Hidden_a_full_row_is_never_played_into()
    {
        Duel duel = _rivals.StartDuel(_cards, 2, 5);
        duel.Advance();
        for (int lane = 0; lane < Keeper.Lanes; lane++)
            duel.Keepers[0].Row[lane] = new Wisp("ember_mote", 1, 2);
        duel.Keepers[0].Kindling = 6;
        duel.Keepers[0].Hand = new List<string> { "lantern_heron", "flare" };
        AssertThat(new Ai().Choose(duel, 0)).IsEqual(1);
        duel.Keepers[0].Hand = new List<string> { "lantern_heron", "fen_stalker" };
        AssertThat(new Ai().Choose(duel, 0)).IsEqual(-1);
    }
}
