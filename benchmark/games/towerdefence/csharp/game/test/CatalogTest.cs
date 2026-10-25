namespace Bramblegate.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// The data's meaning, past what data.json checks: upgrades that make towers better for more sap, maps with a way
/// through, and waves numbered in order.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class CatalogTest
{
    private Catalog _catalog = null!;

    [BeforeTest]
    public void Load() => _catalog = Catalog.FromFiles();

    [TestCase]
    public void Every_tower_has_two_upgrades_each_better_and_dearer()
    {
        foreach (string id in _catalog.TowerIds)
        {
            AssertThat(_catalog.MaxLevel(id)).OverrideFailureMessage(id).IsEqual(3);
            TowerStats last = _catalog.Stats(id, 1);
            foreach (int level in new[] { 2, 3 })
            {
                TowerStats now = _catalog.Stats(id, level);
                AssertThat(now.Damage).OverrideFailureMessage($"{id} level {level} hits harder").IsGreater(last.Damage);
                AssertThat(now.Range >= last.Range).OverrideFailureMessage($"{id} level {level} reaches as far").IsTrue();
                AssertThat(now.Reload <= last.Reload).OverrideFailureMessage($"{id} level {level} fires as often").IsTrue();
                last = now;
            }
            AssertThat(_catalog.UpgradeCost(id, 3)).OverrideFailureMessage(id).IsGreater(_catalog.UpgradeCost(id, 2));
        }
    }

    [TestCase]
    public void Every_map_has_one_gate_one_store_and_a_way_between()
    {
        foreach (MapRow row in _catalog.Maps)
        {
            int gates = 0;
            int stores = 0;
            foreach (string line in row.Rows)
            {
                AssertThat(line.Length).OverrideFailureMessage(row.Id).IsEqual(16);
                gates += line.Split('S').Length - 1;
                stores += line.Split('G').Length - 1;
            }
            AssertThat(gates).OverrideFailureMessage(row.Id).IsEqual(1);
            AssertThat(stores).OverrideFailureMessage(row.Id).IsEqual(1);
            AssertThat(PathMap.FromRows(row.Rows).Route).OverrideFailureMessage(row.Id).IsNotEmpty();
        }
    }

    [TestCase]
    public void Waves_are_numbered_from_one_and_send_known_pests()
    {
        foreach (MapRow row in _catalog.Maps)
        {
            var waves = _catalog.WavesFor(row.Id);
            AssertThat(waves.Count).OverrideFailureMessage(row.Id).IsGreater(0);
            for (int i = 0; i < waves.Count; i++)
            {
                AssertThat(waves[i].Number).OverrideFailureMessage(row.Id).IsEqual(i + 1);
                AssertThat(waves[i].Groups.Count).OverrideFailureMessage($"{row.Id} wave {i + 1}").IsGreater(0);
                foreach (GroupRow group in waves[i].Groups)
                    AssertThat(_catalog.Enemies.ContainsKey(group.Enemy)).OverrideFailureMessage(group.Enemy).IsTrue();
            }
        }
    }

    [TestCase]
    public void The_maps_come_in_campaign_order()
    {
        AssertThat(_catalog.MapAt(1)!.Id).IsEqual("meadow");
        for (int i = 1; i < _catalog.MapCount; i++)
            AssertThat(_catalog.MapAt(i)!.Order).IsLess(_catalog.MapAt(i + 1)!.Order);
    }
}
