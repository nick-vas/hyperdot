namespace Lanternfen.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Deck: the shuffle follows the seed and nothing else, and what makes a deck legal.</summary>
[TestSuite]
[RequireGodotRuntime]
public class DeckTest
{
    /// <summary>The top six cards of the keeper deck shuffled with seed 7: the GDScript version deals the same.</summary>
    private static readonly string[] Pinned7 = { "flare", "lantern_heron", "rekindle", "flare", "ember_mote", "mending_oil" };

    private Cards _cards = null!;
    private List<string> _keeperDeck = null!;

    [BeforeTest]
    public void Load()
    {
        _cards = Cards.FromFile();
        _keeperDeck = Rivals.FromFiles().DeckOf(Rivals.KeeperDeck);
    }

    private List<string> ShuffledWith(long seed)
    {
        var rng = new RandomNumberGenerator { Seed = (ulong)seed };
        return Deck.Shuffled(_keeperDeck, rng);
    }

    [TestCase]
    public void A_seed_always_deals_the_same_deck()
    {
        AssertThat(ShuffledWith(42)).ContainsExactly(ShuffledWith(42));
    }

    [TestCase]
    public void Seed_7_deals_this_order()
    {
        AssertThat(ShuffledWith(7).GetRange(0, 6)).ContainsExactly(Pinned7);
    }

    [TestCase]
    public void Different_seeds_deal_differently()
    {
        var seen = new HashSet<string>();
        for (int seed = 1; seed <= 20; seed++)
            seen.Add(string.Join("/", ShuffledWith(seed)));
        AssertThat(seen.Count).IsGreater(18);
    }

    [TestCase]
    public void A_shuffle_keeps_every_card()
    {
        var sortedBefore = new List<string>(_keeperDeck);
        sortedBefore.Sort(string.CompareOrdinal);
        List<string> after = ShuffledWith(3);
        after.Sort(string.CompareOrdinal);
        AssertThat(after).ContainsExactly(sortedBefore);
    }

    [TestCase]
    public void A_deck_with_a_third_copy_or_too_few_cards_is_not_legal()
    {
        AssertThat(Deck.Problems(_keeperDeck, _cards)).IsEmpty();
        var bad = new List<string>(_keeperDeck);
        bad[0] = "flare";
        AssertThat(Deck.Problems(bad, _cards)).ContainsExactly("3 copies of flare");
        AssertThat(Deck.Problems(_keeperDeck.GetRange(1, _keeperDeck.Count - 1), _cards)).ContainsExactly("19 cards, not 20");
    }
}
