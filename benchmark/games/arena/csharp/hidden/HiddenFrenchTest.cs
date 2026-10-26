namespace Glimmerpit.Tests;

using System;
using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the beta milestone: French, every key translated, the HUD and the menus in French.</summary>
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
        AssertThat(Array.IndexOf(TranslationServer.GetLoadedLocales(), "fr")).IsGreaterEqual(0);
    }

    [TestCase]
    public void Hidden_every_key_has_french()
    {
        using var file = Godot.FileAccess.Open("res://i18n/strings.csv", Godot.FileAccess.ModeFlags.Read);
        string[] header = file.GetCsvLine();
        int fr = Array.IndexOf(header, "fr");
        AssertThat(fr).OverrideFailureMessage("an fr column").IsGreater(0);
        int line = 1;
        while (!file.EofReached())
        {
            string[] cells = file.GetCsvLine();
            line++;
            if (cells.Length <= 1 && (cells.Length == 0 || cells[0] == ""))
                continue;
            AssertThat(cells.Length > fr && cells[fr].StripEdges() != "").OverrideFailureMessage($"line {line} ({cells[0]}) has French").IsTrue();
        }
    }

    [TestCase]
    public async Task Hidden_the_hud_speaks_french()
    {
        TranslationServer.SetLocale("fr");
        var game = GD.Load<PackedScene>("res://game/game.tscn").Instantiate<Game>();
        var tree = (SceneTree)Engine.GetMainLoop();
        tree.Root.AddChild(game);
        try
        {
            for (int i = 0; i < ArenaMatch.WarmupTicks + 4; i++)
                await game.ToSignal(tree, SceneTree.SignalName.PhysicsFrame);
            string label = game.GetNode<Label>("HUD/RoundLabel").Text;
            AssertThat(label).OverrideFailureMessage("the round label is in French").IsNotEqual("Round 1");
            AssertThat(label.Contains('1')).OverrideFailureMessage($"and still shows the round: {label}").IsTrue();
        }
        finally
        {
            game.QueueFree();
        }
    }
}
