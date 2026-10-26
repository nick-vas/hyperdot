namespace Duskhive.Tests;

using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-bug: on a portrait phone, every button of the bottom bar is on the screen in every
/// language the game ships, and in a made-up one whose words are longer still.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenBarFitsTest
{
    private static readonly Vector2I Phone = new(1080, 2400);

    private Vector2I _size;
    private string _locale = "en";
    private Translation _long = null!;

    private static SceneTree Tree => (SceneTree)Engine.GetMainLoop();

    [Before]
    public void AddLongLanguage()
    {
        _size = Tree.Root.Size;
        _locale = TranslationServer.GetLocale();
        _long = new Translation { Locale = "xx" };
        foreach (string key in new[] { "BAR_PRODUCERS", "BAR_UPGRADES", "BAR_DAWN", "BAR_SETTINGS" })
            _long.AddMessage(key, "Morgendämmerungsverbesserungen");
        TranslationServer.AddTranslation(_long);
    }

    [After]
    public void RemoveLongLanguage()
    {
        TranslationServer.RemoveTranslation(_long);
        TranslationServer.SetLocale(_locale);
        Tree.Root.Size = _size;
    }

    private static async Task Check(string locale)
    {
        TranslationServer.SetLocale(locale);
        Tree.Root.Size = Phone;
        var game = GD.Load<PackedScene>("res://game/game.tscn").Instantiate<Game>();
        Tree.Root.AddChild(game);
        try
        {
            for (int i = 0; i < 3; i++)
                await game.ToSignal(Tree, SceneTree.SignalName.PhysicsFrame);
            for (int i = 0; i < 3; i++)
                await game.ToSignal(Tree, SceneTree.SignalName.ProcessFrame);
            Rect2 screen = game.GetViewport().GetVisibleRect();
            foreach (string name in new[] { "ProducersTab", "UpgradesTab", "DawnButton", "SettingsButton" })
            {
                Rect2 rect = game.GetNode<Button>($"Safe/Column/Bar/{name}").GetGlobalRect();
                AssertThat(screen.Encloses(rect.Grow(-0.5f))).OverrideFailureMessage($"{name} in {locale}: {rect} is outside the screen {screen}").IsTrue();
                AssertThat(rect.Size.X).OverrideFailureMessage($"{name} in {locale} is still a button").IsGreaterEqual(60.0f);
            }
            AssertThat(game.GetNode<Control>("Safe/Column").Size.X).OverrideFailureMessage($"the column fits the screen in {locale}").IsLessEqual(screen.Size.X);
        }
        finally
        {
            Tree.Root.RemoveChild(game);
            game.QueueFree();
        }
    }

    [TestCase]
    public async Task Hidden_the_bar_fits_in_english() => await Check("en");

    [TestCase]
    public async Task Hidden_the_bar_fits_in_german() => await Check("de");

    [TestCase]
    public async Task Hidden_the_bar_fits_longer_words() => await Check("xx");
}
