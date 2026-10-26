namespace Duskhive;

/// <summary>One decision of the bot: Kind is "dawn", "upgrade", "buy", "gather" or "wait"; Id the upgrade or producer.</summary>
public sealed record BotAction(string Kind, string Id);

/// <summary>
/// The --autoplay player. Each decision: dawn once a dawn would at least double the embers, else take any upgrade it
/// can pay for, else buy the producer that pays its price back soonest, or wait for it. With nothing to wait for, it
/// gathers. Deterministic: the same economy gives the same choice.
/// </summary>
public static class Bot
{
    /// <summary>What to do now.</summary>
    public static BotAction NextAction(Economy economy)
    {
        double gain = economy.DawnGain();
        if (gain >= 1.0 && gain >= economy.Embers)
            return new BotAction("dawn", "");
        foreach (UpgradeData u in economy.Catalog.Upgrades)
        {
            if (economy.CanUpgrade(u.Id))
                return new BotAction("upgrade", u.Id);
        }
        string best = "";
        double bestPayback = double.PositiveInfinity;
        foreach (ProducerData p in economy.Catalog.Producers)
        {
            double payback = economy.Cost(p.Id, 1) / System.Math.Max(economy.UnitRate(p.Id), 1e-9);
            if (payback < bestPayback)
            {
                bestPayback = payback;
                best = p.Id;
            }
        }
        if (best != "" && economy.CanBuy(best))
            return new BotAction("buy", best);
        if (economy.Rate() <= 0.0)
            return new BotAction("gather", "");
        return new BotAction("wait", best);
    }

    /// <summary>Carries out NextAction(); what it did.</summary>
    public static BotAction Act(Economy economy)
    {
        BotAction action = NextAction(economy);
        switch (action.Kind)
        {
            case "dawn":
                economy.Dawn();
                break;
            case "upgrade":
                economy.BuyUpgrade(action.Id);
                break;
            case "buy":
                economy.Buy(action.Id);
                break;
            case "gather":
                economy.Tap();
                break;
        }
        return action;
    }
}
