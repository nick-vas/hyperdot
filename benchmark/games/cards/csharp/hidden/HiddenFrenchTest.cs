namespace Lanternfen.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Hidden acceptance for the alpha-to-beta milestone: the game ships in French, menus and cards included.</summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenFrenchTest
{
    [AfterTest]
    public void English()
    {
        TranslationServer.SetLocale("en");
    }

    [TestCase]
    public void Hidden_french_is_loaded()
    {
        AssertThat(new List<string>(TranslationServer.GetLoadedLocales())).Contains("fr");
    }

    [TestCase]
    public void Hidden_menu_and_cards_are_translated()
    {
        foreach (string key in new[] { "MENU_START", "CARD_FLARE", "RIVAL_5" })
        {
            TranslationServer.SetLocale("en");
            string english = TranslationServer.Translate(key).ToString();
            TranslationServer.SetLocale("fr");
            string french = TranslationServer.Translate(key).ToString();
            AssertThat(french).OverrideFailureMessage(key).IsNotEqual(key);
            AssertThat(french).OverrideFailureMessage(key).IsNotEqual(english);
        }
    }
}
