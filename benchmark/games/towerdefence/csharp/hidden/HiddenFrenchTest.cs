namespace Bramblegate.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Hidden acceptance for the alpha-to-beta milestone: the game ships in French, menus, maps and towers included.</summary>
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
    public void Hidden_menu_maps_and_towers_are_translated()
    {
        Catalog catalog = Catalog.FromFiles();
        var keys = new List<string> { "MENU_START", catalog.MapAt(3)!.Name };
        foreach (string id in catalog.TowerIds)
            keys.Add(catalog.Towers[id].Name);
        foreach (string key in keys)
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
