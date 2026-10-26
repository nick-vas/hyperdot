namespace Duskhive.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Bot: the --autoplay player's choices.</summary>
[TestSuite]
[RequireGodotRuntime]
public class BotTest
{
    private Economy _economy = null!;

    [BeforeTest]
    public void Start() => _economy = new Economy(Catalog.FromFiles());

    [TestCase]
    public void With_nothing_it_gathers()
    {
        AssertThat(Bot.NextAction(_economy).Kind).IsEqual("gather");
    }

    [TestCase]
    public void It_buys_what_pays_back_soonest()
    {
        _economy.Glow = 200.0;
        BotAction action = Bot.NextAction(_economy);
        AssertThat(action.Kind).IsEqual("buy");
        AssertThat(action.Id).IsEqual("wick_moth");
    }

    [TestCase]
    public void It_takes_an_upgrade_it_can_pay_for()
    {
        _economy.SetCount("wick_moth", 10);
        _economy.Glow = 160.0;
        AssertThat(Bot.NextAction(_economy)).IsEqual(new BotAction("upgrade", "twin_wicks"));
    }

    [TestCase]
    public void It_dawns_once_the_dawn_doubles_its_embers()
    {
        _economy.Embers = 3.0;
        _economy.Earn(9e6);
        AssertThat(Bot.NextAction(_economy).Kind).IsEqual("dawn");
        _economy.Embers = 4.0;
        AssertThat(Bot.NextAction(_economy).Kind).IsNotEqual("dawn");
    }
}
