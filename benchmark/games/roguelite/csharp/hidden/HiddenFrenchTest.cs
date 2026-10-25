namespace Wickerdeep.Tests;

using System.Collections.Generic;
using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Hidden acceptance for the alpha-to-beta milestone: French, every visible text translated.</summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenFrenchTest
{
    [AfterTest]
    public void English()
    {
        TranslationServer.SetLocale("en");
    }

    private static string Translate(string key, string locale)
    {
        TranslationServer.SetLocale(locale);
        return TranslationServer.Translate(key).ToString();
    }

    [TestCase]
    public void Hidden_french_is_loaded()
    {
        AssertThat(new List<string>(TranslationServer.GetLoadedLocales())).Contains("fr");
    }

    [TestCase]
    public void Hidden_the_hud_and_floors_read_in_french()
    {
        foreach (string key in new[] { "MENU_START", "MENU_SHRINE", "HUD_ENEMIES", "HUD_STAIRS_OPEN", "RUN_LOST", "RUN_AGAIN", "PAUSE_RESUME", "SHRINE_TITLE" })
        {
            string english = Translate(key, "en");
            string french = Translate(key, "fr");
            AssertThat(french).OverrideFailureMessage($"{key} has a French text").IsNotEqual(key);
            AssertThat(french).OverrideFailureMessage($"{key} is not left in English").IsNotEqual(english);
        }
        Floors floors = Floors.FromFiles();
        for (int number = 1; number <= floors.Count; number++)
        {
            string name = floors.Spec(number)!.Name;
            AssertThat(Translate(name, "fr")).IsNotEqual(name);
        }
    }

    [TestCase]
    public async Task Hidden_the_menu_reads_in_french()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://main.tscn");
        Node main = runner.Scene();
        await runner.SimulateFrames(2);
        TranslationServer.SetLocale("fr");
        await runner.SimulateFrames(2);
        AssertThat(main.GetNode<Button>("Menu/StartButton").Text).IsEqual("Descendre");
    }
}
