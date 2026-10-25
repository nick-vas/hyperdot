namespace Lanternfen.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-bug: a seed always deals the same cards, whatever the global generator did before,
/// seeds that differ deal differently, and shuffling leaves the global generator alone.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenShuffleTest
{
    private Cards _cards = null!;
    private Rivals _rivals = null!;

    [BeforeTest]
    public void Load()
    {
        _cards = Cards.FromFile();
        _rivals = Rivals.FromFiles();
    }

    private List<string> Deal(long seed)
    {
        var rng = new RandomNumberGenerator { Seed = (ulong)seed };
        return Deck.Shuffled(_rivals.DeckOf(Rivals.KeeperDeck), rng);
    }

    [TestCase]
    public void Hidden_the_same_seed_deals_the_same_in_any_order()
    {
        List<string> first = Deal(2026);
        GD.Randomize();
        Deal(5);
        GD.Randomize();
        AssertThat(Deal(2026)).ContainsExactly(first);
    }

    [TestCase]
    public void Hidden_two_duels_with_one_seed_deal_the_same_hands()
    {
        Duel first = _rivals.StartDuel(_cards, 3, 77);
        GD.Randomize();
        Duel second = _rivals.StartDuel(_cards, 3, 77);
        for (int seat = 0; seat < 2; seat++)
        {
            AssertThat(second.Keepers[seat].Hand).OverrideFailureMessage($"seat {seat} hand").ContainsExactly(first.Keepers[seat].Hand);
            AssertThat(second.Keepers[seat].Deck).OverrideFailureMessage($"seat {seat} deck").ContainsExactly(first.Keepers[seat].Deck);
        }
    }

    [TestCase]
    public void Hidden_seeds_that_differ_deal_differently()
    {
        var seen = new HashSet<string>();
        for (int seed = 100; seed < 130; seed++)
            seen.Add(string.Join("/", Deal(seed)));
        AssertThat(seen.Count).IsGreater(25);
    }

    [TestCase]
    public void Hidden_shuffling_leaves_the_global_generator_alone()
    {
        GD.Seed(99);
        uint expected = GD.Randi();
        GD.Seed(99);
        Deal(7);
        _rivals.StartDuel(_cards, 1, 8);
        AssertThat(GD.Randi()).IsEqual(expected);
    }
}
