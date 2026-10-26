namespace Cinderloop.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden acceptance for the alpha-to-beta milestone: the game ships French, with every key the menus, HUD and tracks
/// use translated.
/// </summary>
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
    public void Hidden_the_menus_and_tracks_are_in_french()
    {
        TranslationServer.SetLocale("fr");
        foreach (string key in new[] { "MENU_START", "MENU_SETTINGS", "MENU_QUIT", "SELECT_TITLE", "PAUSE_RESUME", "TRACK_1", "TRACK_2", "TRACK_3", "SETTINGS_TITLE" })
        {
            string french = TranslationServer.Translate(key).ToString();
            AssertThat(french).OverrideFailureMessage($"{key} has a French text").IsNotEqual(key);
            TranslationServer.SetLocale("en");
            AssertThat(french).OverrideFailureMessage($"{key} differs from the English").IsNotEqual(TranslationServer.Translate(key).ToString());
            TranslationServer.SetLocale("fr");
        }
    }
}
