namespace Lanternfen.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden acceptance for the alpha-to-beta milestone: five rivals, each with a legal deck, each beaten by the player's
/// deck in some seeded duels and none beaten in all of them.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenFiveRivalsTest
{
    [TestCase]
    public void Hidden_five_rivals_each_fair()
    {
        Cards cards = Cards.FromFile();
        Rivals rivals = Rivals.FromFiles();
        AssertThat(rivals.Count).IsGreaterEqual(5);
        for (int id = 1; id <= 5; id++)
        {
            var deck = rivals.DeckOf(rivals.Rival(id)!.Deck);
            AssertThat(Deck.Problems(deck, cards)).OverrideFailureMessage($"rival {id}").IsEmpty();
            int wins = 0;
            for (int seed = 1; seed <= 20; seed++)
            {
                if (Ai.PlayOut(rivals.StartDuel(cards, id, seed), new[] { new Ai(), rivals.AiFor(id) }) == 0)
                    wins += 1;
            }
            AssertThat(wins).OverrideFailureMessage($"rival {id}: the player won {wins} of 20").IsBetween(1, 19);
        }
    }
}
