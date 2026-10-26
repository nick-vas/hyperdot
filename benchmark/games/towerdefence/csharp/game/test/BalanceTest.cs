namespace Bramblegate.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Balance: the bot's build clears every map over several seeds without having it easy, and a field with no tower
/// loses every map early.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class BalanceTest
{
    private Catalog _catalog = null!;

    [BeforeTest]
    public void Load() => _catalog = Catalog.FromFiles();

    [TestCase]
    public void The_bot_clears_every_map()
    {
        foreach (MapRow row in _catalog.Maps)
        {
            foreach (int seed in new[] { 1, 2, 3 })
            {
                Battle battle = Battle.Create(_catalog, row.Id, seed)!;
                AssertThat(Bot.Play(battle)).OverrideFailureMessage($"{row.Id}, seed {seed}: lost at wave {battle.Wave}").IsTrue();
            }
        }
    }

    [TestCase]
    public void The_campaign_costs_the_bot_some_seeds()
    {
        int lost = 0;
        foreach (MapRow row in _catalog.Maps)
        {
            Battle battle = Battle.Create(_catalog, row.Id, 1)!;
            Bot.Play(battle);
            lost += battle.StartLives - battle.Lives;
        }
        AssertThat(lost).OverrideFailureMessage("lost along the way").IsBetween(1, 30);
    }

    [TestCase]
    public void No_tower_loses_every_map_before_its_last_wave()
    {
        foreach (MapRow row in _catalog.Maps)
        {
            Battle battle = Battle.Create(_catalog, row.Id, 1)!;
            AssertThat(Bot.Idle(battle)).OverrideFailureMessage(row.Id).IsFalse();
            AssertThat(battle.Wave).OverrideFailureMessage(row.Id).IsLess(battle.Waves.Count);
        }
    }
}
