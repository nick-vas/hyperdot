namespace Lanternfen.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Rivals: each has a name, a legal deck and an AI, and the player's deck can beat each of them.</summary>
[TestSuite]
[RequireGodotRuntime]
public class RivalsTest
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
    public void The_rivals_are_numbered_from_one()
    {
        AssertThat(_rivals.Count).IsGreaterEqual(3);
        for (int id = 1; id <= _rivals.Count; id++)
        {
            AssertThat(_rivals.HasRival(id)).OverrideFailureMessage($"rival {id}").IsTrue();
            AssertThat(_rivals.Rival(id)!.Name).StartsWith("RIVAL_");
        }
    }

    [TestCase]
    public void Every_deck_is_legal()
    {
        AssertThat(Deck.Problems(_rivals.DeckOf(Rivals.KeeperDeck), _cards)).OverrideFailureMessage("the keeper's deck").IsEmpty();
        for (int id = 1; id <= _rivals.Count; id++)
        {
            var problems = Deck.Problems(_rivals.DeckOf(_rivals.Rival(id)!.Deck), _cards);
            AssertThat(problems).OverrideFailureMessage($"rival {id}: {string.Join(", ", problems)}").IsEmpty();
        }
    }

    [TestCase]
    public void Every_rival_can_be_beaten_and_can_win()
    {
        for (int id = 1; id <= _rivals.Count; id++)
        {
            int wins = 0;
            for (int seed = 1; seed <= 20; seed++)
            {
                int winner = Ai.PlayOut(_rivals.StartDuel(_cards, id, seed), new[] { new Ai(), _rivals.AiFor(id) });
                AssertThat(winner >= 0).OverrideFailureMessage($"rival {id} seed {seed} ended ({winner})").IsTrue();
                if (winner == 0)
                    wins += 1;
            }
            AssertThat(wins).OverrideFailureMessage($"rival {id}: the player won {wins} of 20").IsBetween(1, 19);
        }
    }
}
