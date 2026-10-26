namespace Bramblegate.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the alpha's add-content: the moth, the Sunken Path's fifth wave, and the map still fair.</summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenMothTest
{
    private Catalog _catalog = null!;

    [BeforeTest]
    public void Load() => _catalog = Catalog.FromFiles();

    [TestCase]
    public void Hidden_the_moth_is_the_fastest_pest()
    {
        AssertThat(_catalog.Enemies.ContainsKey("moth")).IsTrue();
        EnemyRow moth = _catalog.Enemies["moth"];
        AssertThat(moth.Speed).IsEqualApprox(2.4, 0.001);
        AssertThat(moth.Hp).IsEqual(34);
        AssertThat(moth.Reward).IsEqual(6);
        AssertThat(moth.Leak).IsEqual(1);
        foreach (string id in _catalog.EnemyIds)
        {
            if (id != "moth")
                AssertThat(_catalog.Enemies[id].Speed).OverrideFailureMessage(id).IsLess(moth.Speed);
        }
        AssertThat(moth.Name).IsEqual("ENEMY_MOTH");
        AssertThat(TranslationServer.Translate("ENEMY_MOTH").ToString()).OverrideFailureMessage("named in the translation table").IsNotEqual("ENEMY_MOTH");
    }

    [TestCase]
    public void Hidden_the_sunken_path_has_a_fifth_wave_of_moths_and_beetles()
    {
        var waves = _catalog.WavesFor("sunken");
        AssertThat(waves.Count).IsEqual(5);
        WaveRow fifth = waves[4];
        AssertThat(fifth.Number).IsEqual(5);
        AssertThat(fifth.Bonus).IsEqual(45);
        int moths = 0;
        int beetles = 0;
        foreach (GroupRow group in fifth.Groups)
        {
            if (group.Enemy == "moth")
                moths += group.Count;
            else if (group.Enemy == "beetle")
                beetles += group.Count;
        }
        AssertThat(moths).IsGreaterEqual(12);
        AssertThat(beetles).IsGreater(0);
    }

    [TestCase]
    public void Hidden_the_sunken_path_stays_fair()
    {
        foreach (int seed in new[] { 1, 2, 3 })
        {
            Battle battle = Battle.Create(_catalog, "sunken", seed)!;
            AssertThat(Bot.Play(battle)).OverrideFailureMessage($"seed {seed}: lost at wave {battle.Wave}").IsTrue();
        }
        AssertThat(Bot.Idle(Battle.Create(_catalog, "sunken", 1)!)).IsFalse();
    }
}
