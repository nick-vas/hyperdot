namespace Duskhive;

using System;
using System.Collections.Generic;
using System.Text.Json.Nodes;

/// <summary>
/// The glow economy, without nodes or the clock: producers bought with glow at prices that grow geometrically,
/// upgrades that multiply what they make, and the dawn, the reset that trades a run's glow for embers. Every amount is
/// a double (Numbers). The rate is worked out once per change and kept, so a tick costs the same however much is owned.
/// </summary>
public sealed class Economy
{
    private readonly Dictionary<string, int> _owned = new();
    private readonly Dictionary<string, double> _rates = new();
    private double _rate;
    private bool _dirty = true;

    public Economy(Catalog? catalog = null)
    {
        Catalog = catalog ?? Catalog.FromFiles();
    }

    public event Action<string, int>? Bought;
    public event Action<string>? Upgraded;
    public event Action<double>? Dawned;

    public Catalog Catalog { get; }

    public double Glow { get; set; }

    /// <summary>Glow earned since the last dawn, spent or not: what the next dawn pays for.</summary>
    public double RunEarned { get; set; }

    /// <summary>Glow earned in all runs.</summary>
    public double TotalEarned { get; set; }

    /// <summary>Producer id -> how many are owned; SetCount changes it.</summary>
    public IReadOnlyDictionary<string, int> Owned => _owned;

    /// <summary>The upgrades bought this run, by id.</summary>
    public HashSet<string> Upgrades { get; } = new();

    public double Embers { get; set; }

    public int Dawns { get; set; }

    /// <summary>How many times the rate was worked out from scratch: for the performance tests.</summary>
    public int RateComputations { get; private set; }

    public int Count(string id) => _owned.TryGetValue(id, out int n) ? n : 0;

    /// <summary>Sets how many of a producer are owned, as a save or a test has it; the rate is worked out again.</summary>
    public void SetCount(string id, int count)
    {
        _owned[id] = count;
        _dirty = true;
    }

    /// <summary>What the next amount of a producer cost together, at its price now.</summary>
    public double Cost(string id, int amount = 1)
    {
        ProducerData? p = Catalog.Producer(id);
        if (p == null || amount < 1)
            return double.PositiveInfinity;
        double first = p.Cost;
        double g = p.Growth;
        int n = Count(id);
        if (amount == 1)
            return first * Numbers.Power(g, n);
        // The sum of the next amount prices, first * g^n + ... + first * g^(n + amount - 1).
        return first * (Numbers.Power(g, n + amount) - Numbers.Power(g, n)) / (g - 1.0);
    }

    /// <summary>The most of a producer the glow pays for now.</summary>
    public int MaxAffordable(string id)
    {
        if (Catalog.Producer(id) == null || Cost(id, 1) > Glow)
            return 0;
        // Double until it costs too much, then halve the gap: exact at the boundary, and no Math.Log.
        int low = 1;
        int high = 2;
        while (Cost(id, high) <= Glow)
        {
            low = high;
            high *= 2;
        }
        while (high - low > 1)
        {
            int middle = low + (high - low) / 2;
            if (Cost(id, middle) <= Glow)
                low = middle;
            else
                high = middle;
        }
        return low;
    }

    public bool CanBuy(string id, int amount = 1) => amount >= 1 && Catalog.Producer(id) != null && Cost(id, amount) <= Glow;

    public bool Buy(string id, int amount = 1)
    {
        if (!CanBuy(id, amount))
            return false;
        Glow -= Cost(id, amount);
        _owned[id] = Count(id) + amount;
        _dirty = true;
        Bought?.Invoke(id, amount);
        return true;
    }

    /// <summary>Buys as many of a producer as the glow pays for; how many.</summary>
    public int BuyMax(string id)
    {
        int amount = MaxAffordable(id);
        if (amount > 0)
            Buy(id, amount);
        return amount;
    }

    /// <summary>Whether an upgrade is on offer: not bought yet, and its producer owned often enough ("all": all producers together).</summary>
    public bool UpgradeUnlocked(string id)
    {
        UpgradeData? u = Catalog.Upgrade(id);
        if (u == null || Upgrades.Contains(id))
            return false;
        if (u.Target == "all")
        {
            int total = 0;
            foreach (ProducerData p in Catalog.Producers)
                total += Count(p.Id);
            return total >= u.Needs;
        }
        if (u.Target == "tap")
            return true;
        return Count(u.Target) >= u.Needs;
    }

    public bool CanUpgrade(string id) => UpgradeUnlocked(id) && Catalog.Upgrade(id)!.Cost <= Glow;

    public bool BuyUpgrade(string id)
    {
        if (!CanUpgrade(id))
            return false;
        Glow -= Catalog.Upgrade(id)!.Cost;
        Upgrades.Add(id);
        _dirty = true;
        Upgraded?.Invoke(id);
        return true;
    }

    /// <summary>What upgrades and milestones multiply a producer by (or the tap, for "tap").</summary>
    public double Multiplier(string id)
    {
        double m = 1.0;
        foreach (UpgradeData u in Catalog.Upgrades)
        {
            if (Upgrades.Contains(u.Id) && (u.Target == id || (u.Target == "all" && id != "tap")))
                m *= u.Multiplier;
        }
        int every = (int)Catalog.Setting("milestone_every");
        if (id != "tap" && every > 0)
            m *= Numbers.Power(Catalog.Setting("milestone_multiplier"), (int)Math.Floor(Count(id) / (double)every));
        return m;
    }

    /// <summary>What every ember adds to production.</summary>
    public double EmberMultiplier() => 1.0 + Embers * Catalog.Setting("ember_bonus");

    /// <summary>Glow per second from everything owned.</summary>
    public double Rate()
    {
        if (_dirty)
            Recompute();
        return _rate;
    }

    /// <summary>Glow per second from one producer.</summary>
    public double ProducerRate(string id)
    {
        if (_dirty)
            Recompute();
        return _rates.TryGetValue(id, out double r) ? r : 0.0;
    }

    /// <summary>What one more of a producer would add per second (its next milestone left out).</summary>
    public double UnitRate(string id)
    {
        ProducerData? p = Catalog.Producer(id);
        return p == null ? 0.0 : p.Rate * Multiplier(id) * EmberMultiplier();
    }

    private void Recompute()
    {
        RateComputations++;
        _rates.Clear();
        _rate = 0.0;
        foreach (ProducerData p in Catalog.Producers)
        {
            double r = p.Rate * Count(p.Id) * Multiplier(p.Id) * EmberMultiplier();
            _rates[p.Id] = r;
            _rate += r;
        }
        _dirty = false;
    }

    /// <summary>Glow for one press of Gather.</summary>
    public double TapValue() => Catalog.Setting("tap") * Multiplier("tap");

    public double Tap()
    {
        double value = TapValue();
        Earn(value);
        return value;
    }

    /// <summary>Lets the given seconds of production pass; what they earned.</summary>
    public double Tick(double seconds)
    {
        if (seconds <= 0.0)
            return 0.0;
        double earned = Rate() * seconds;
        Glow = Math.Min(Glow + earned, Numbers.Max);
        return earned;
    }

    public void Earn(double amount)
    {
        Glow = Math.Min(Glow + amount, Numbers.Max);
        RunEarned = Math.Min(RunEarned + amount, Numbers.Max);
        TotalEarned = Math.Min(TotalEarned + amount, Numbers.Max);
    }

    /// <summary>Embers a dawn now would give: the square root of the run's glow over the dawn base, rounded down.</summary>
    public double DawnGain() => Math.Floor(Math.Sqrt(Math.Max(RunEarned, Glow) / Catalog.Setting("dawn_base")));

    public bool CanDawn() => DawnGain() >= 1.0;

    /// <summary>The prestige reset: glow, producers and upgrades go, embers stay and grow. Returns the embers gained (0: not yet).</summary>
    public double Dawn()
    {
        double gain = DawnGain();
        if (gain < 1.0)
            return 0.0;
        Embers += gain;
        Dawns++;
        Glow = 0.0;
        RunEarned = 0.0;
        _owned.Clear();
        Upgrades.Clear();
        _dirty = true;
        Dawned?.Invoke(gain);
        return gain;
    }

    public JsonObject ToDict()
    {
        // In data order, so the same economy always writes the same file.
        var owned = new JsonObject();
        foreach (ProducerData p in Catalog.Producers)
        {
            if (_owned.TryGetValue(p.Id, out int n))
                owned[p.Id] = n;
        }
        var upgrades = new JsonArray();
        foreach (UpgradeData u in Catalog.Upgrades)
        {
            if (Upgrades.Contains(u.Id))
                upgrades.Add(u.Id);
        }
        return new JsonObject
        {
            ["glow"] = Glow,
            ["run_earned"] = RunEarned,
            ["total_earned"] = TotalEarned,
            ["owned"] = owned,
            ["upgrades"] = upgrades,
            ["prestige"] = new JsonObject { ["embers"] = Embers, ["dawns"] = Dawns },
        };
    }

    /// <summary>An economy from ToDict()'s data; anything missing or of the wrong kind starts at zero.</summary>
    public static Economy FromDict(Catalog catalog, JsonObject data)
    {
        var e = new Economy(catalog);
        e.Glow = Amount(data, "glow", 0.0);
        e.RunEarned = Amount(data, "run_earned", e.Glow);
        e.TotalEarned = Math.Max(Amount(data, "total_earned", e.RunEarned), e.RunEarned);
        if (data["owned"] is JsonObject owned)
        {
            foreach (KeyValuePair<string, JsonNode?> entry in owned)
            {
                if (catalog.Producer(entry.Key) != null)
                    e._owned[entry.Key] = Math.Max(0, JsonData.Int(entry.Value, 0));
            }
        }
        foreach (string id in JsonData.Ids(data["upgrades"]))
        {
            if (catalog.Upgrade(id) != null)
                e.Upgrades.Add(id);
        }
        if (data["prestige"] is JsonObject prestige)
        {
            e.Embers = Amount(prestige, "embers", 0.0);
            e.Dawns = Math.Max(0, JsonData.Int(prestige["dawns"], 0));
        }
        return e;
    }

    /// <summary>A saved amount: the fallback when it is missing, zero when it is not a number, never past Numbers.Max.</summary>
    private static double Amount(JsonObject data, string key, double missing)
    {
        if (!data.ContainsKey(key))
            return missing;
        double value = JsonData.Number(data[key], double.NaN);
        return double.IsNaN(value) ? 0.0 : Math.Clamp(value, 0.0, Numbers.Max);
    }
}
