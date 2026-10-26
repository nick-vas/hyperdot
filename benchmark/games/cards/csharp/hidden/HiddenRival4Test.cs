namespace Lanternfen.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the alpha's add-content: rival 4, The Heron Knight, with a legal deck that leans on big wisps, 21
/// light, an aggressive AI, and a fair fight: in duels 1 to 20 the player's deck wins at least 5 and loses at least 2.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenRival4Test
{
    private Cards _cards = null!;
    private Rivals _rivals = null!;

    [BeforeTest]
    public void Load()
    {
        _cards = Cards.FromFile();
        _rivals = Rivals.FromFiles();
    }

    [AfterTest]
    public void English()
    {
        TranslationServer.SetLocale("en");
    }

    [TestCase]
    public void Hidden_rival_4_is_the_heron_knight()
    {
        AssertThat(_rivals.HasRival(4)).IsTrue();
        RivalRow entry = _rivals.Rival(4)!;
        TranslationServer.SetLocale("en");
        AssertThat(TranslationServer.Translate(entry.Name).ToString()).IsEqual("The Heron Knight");
        AssertThat(entry.Light).IsEqual(21);
        AssertThat(entry.Aggression).IsGreater(1.0);
    }

    [TestCase]
    public void Hidden_its_own_deck_is_legal_and_leans_on_big_wisps()
    {
        string deckId = _rivals.Rival(4)!.Deck;
        AssertThat(deckId).IsNotEqual(Rivals.KeeperDeck);
        foreach (int id in new[] { 1, 2, 3 })
            AssertThat(deckId).OverrideFailureMessage($"rival {id}'s deck").IsNotEqual(_rivals.Rival(id)!.Deck);
        var deck = _rivals.DeckOf(deckId);
        var problems = Deck.Problems(deck, _cards);
        AssertThat(problems).OverrideFailureMessage(string.Join(", ", problems)).IsEmpty();
        int big = 0;
        foreach (string id in deck)
        {
            Card card = _cards.Get(id);
            if (card.Kind == Cards.Wisp && card.Cost >= 4)
                big += 1;
        }
        AssertThat(big).IsGreaterEqual(4);
    }

    [TestCase]
    public void Hidden_the_fight_is_fair()
    {
        int wins = 0;
        for (int seed = 1; seed <= 20; seed++)
        {
            int winner = Ai.PlayOut(_rivals.StartDuel(_cards, 4, seed), new[] { new Ai(), _rivals.AiFor(4) });
            AssertThat(winner >= 0).OverrideFailureMessage($"seed {seed} ended").IsTrue();
            if (winner == 0)
                wins += 1;
        }
        AssertThat(wins).OverrideFailureMessage($"the player won {wins} of 20").IsBetween(5, 18);
    }
}
