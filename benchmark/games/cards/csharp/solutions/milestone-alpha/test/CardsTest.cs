namespace Lanternfen.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Cards: every card has what its kind needs.</summary>
[TestSuite]
[RequireGodotRuntime]
public class CardsTest
{
    [TestCase]
    public void Every_card_has_what_its_kind_needs()
    {
        Cards cards = Cards.FromFile();
        AssertThat(cards.Ids().Count).IsGreater(0);
        foreach (string id in cards.Ids())
        {
            Card card = cards.Get(id);
            if (card.Kind == Cards.Wisp)
            {
                AssertThat(card.Guard).OverrideFailureMessage($"{id} has a guard").IsGreater(0);
                AssertThat(card.Effect).OverrideFailureMessage($"{id} is a wisp with an effect").IsEqual("");
            }
            else
            {
                AssertThat(card.Kind).OverrideFailureMessage(id).IsEqual(Cards.Rite);
                AssertThat(Cards.Effects).OverrideFailureMessage($"{id} does something").Contains(card.Effect);
                AssertThat(card.Amount).OverrideFailureMessage($"{id} has an amount").IsGreater(0);
            }
        }
    }

    [TestCase]
    public void Every_card_name_is_translated()
    {
        TranslationServer.SetLocale("en");
        Cards cards = Cards.FromFile();
        foreach (string id in cards.Ids())
        {
            string key = cards.Get(id).Name;
            AssertThat(TranslationServer.Translate(key).ToString()).OverrideFailureMessage(id).IsNotEqual(key);
        }
    }
}
