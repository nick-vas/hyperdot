namespace Duskhive.Tests;

using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden acceptance for the alpha-to-beta milestone: the Star Loom, German throughout, the bar on a phone in German,
/// and the bot.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenBetaTest
{
    [TestCase]
    public void Hidden_five_producers()
    {
        Catalog catalog = Catalog.FromFiles();
        var ids = new List<string>();
        foreach (ProducerData p in catalog.Producers)
            ids.Add(p.Id);
        AssertThat(string.Join(",", ids)).IsEqual("wick_moth,glow_snail,firefly_choir,moon_lily,star_loom");
        AssertThat(catalog.Upgrade("star_thread") != null).IsTrue();
    }

    [TestCase]
    public void Hidden_every_text_has_german()
    {
        using FileAccess csv = FileAccess.Open("res://i18n/strings.csv", FileAccess.ModeFlags.Read);
        string[] header = csv.GetCsvLine();
        int de = Array.IndexOf(header, "de");
        AssertThat(de).OverrideFailureMessage("a de column").IsGreater(0);
        int rows = 0;
        while (!csv.EofReached())
        {
            string[] line = csv.GetCsvLine();
            if (line.Length <= 1)
                continue;
            rows++;
            AssertThat(line.Length > de && line[de].StripEdges() != "").OverrideFailureMessage($"{line[0]} in German").IsTrue();
        }
        AssertThat(rows).IsGreater(40);
    }

    [TestCase]
    public async Task Hidden_german_names_on_screen()
    {
        string locale = TranslationServer.GetLocale();
        TranslationServer.SetLocale("de");
        try
        {
            using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
            var game = (Game)runner.Scene();
            for (int i = 0; i < 2; i++)
                await game.ToSignal(game.GetTree(), SceneTree.SignalName.PhysicsFrame);
            string name = game.GetNode<Label>("Safe/Column/ProducerPage/List/WickMothRow/Box/Info/NameLabel").Text;
            AssertThat(name).IsNotEqual("Wick Moth");
            AssertThat(name).IsNotEqual("PRODUCER_WICK_MOTH");
            AssertThat(game.GetNode<Button>("Safe/Column/Bar/SettingsButton").Text).IsNotEqual("Settings");
        }
        finally
        {
            TranslationServer.SetLocale(locale);
        }
    }

    [TestCase]
    public void Hidden_the_bot_plays_from_the_command_line()
    {
        LaunchOptions options = LaunchOptions.Parse(new[] { "--autoplay", "--speed=60", "--no-save" });
        AssertThat(options.Autoplay).IsTrue();
        AssertThat(options.Speed).IsEqual(60.0);
        AssertThat(options.NoSave).IsTrue();
        var economy = new Economy(Catalog.FromFiles());
        for (int second = 0; second < 3600; second++)
        {
            Bot.Act(economy);
            economy.Tick(1.0);
        }
        AssertThat(economy.Dawns).IsGreaterEqual(3);
    }
}
