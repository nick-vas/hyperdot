namespace Lanternfen;

using System.Collections.Generic;
using Godot;

/// <summary>
/// Decks: what makes one legal, and the shuffle. The shuffle draws only from the generator it is given (the duel's own,
/// seeded), so a seed always deals the same cards and a bug report's --seed replays its duel.
/// </summary>
public static class Deck
{
    public const int Size = 20;
    public const int MaxCopies = 2;

    /// <summary>A shuffled copy (Fisher-Yates, from the last card down). The first card of the result is the top of the deck.</summary>
    public static List<string> Shuffled(IEnumerable<string> cards, RandomNumberGenerator rng)
    {
        var shuffled = new List<string>(cards);
        for (int i = shuffled.Count - 1; i > 0; i--)
        {
            int j = rng.RandiRange(0, i);
            (shuffled[i], shuffled[j]) = (shuffled[j], shuffled[i]);
        }
        return shuffled;
    }

    /// <summary>Why a deck is not legal; empty when it is: exactly Size cards, every one in the catalogue, at most MaxCopies of each.</summary>
    public static List<string> Problems(IReadOnlyList<string> cards, Cards catalogue)
    {
        var found = new List<string>();
        if (cards.Count != Size)
            found.Add($"{cards.Count} cards, not {Size}");
        var copies = new Dictionary<string, int>();
        // Counted in the deck's order, so the problems come out in the same order every time.
        var seen = new List<string>();
        foreach (string id in cards)
        {
            if (!catalogue.Has(id))
                found.Add($"no card {id}");
            if (!copies.ContainsKey(id))
            {
                copies[id] = 0;
                seen.Add(id);
            }
            copies[id] += 1;
        }
        foreach (string id in seen)
        {
            if (copies[id] > MaxCopies)
                found.Add($"{copies[id]} copies of {id}");
        }
        return found;
    }
}
