namespace Duskhive;

using System;
using System.Collections.Generic;

/// <summary>
/// The glow economy, without nodes or the clock: producers bought with glow at prices that grow geometrically, and
/// Gather. Every amount is a double (Numbers). The rate is worked out once per change and kept, so a tick costs the
/// same however much is owned.
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

    public Catalog Catalog { get; }

    public double Glow { get; set; }

    /// <summary>Producer id -> how many are owned; SetCount changes it.</summary>
    public IReadOnlyDictionary<string, int> Owned => _owned;

    /// <summary>How many times the rate was worked out from scratch.</summary>
    public int RateComputations { get; private set; }

    public int Count(string id) => _owned.TryGetValue(id, out int n) ? n : 0;

    /// <summary>Sets how many of a producer are owned, as a test has it; the rate is worked out again.</summary>
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

    /// <summary>What milestones multiply a producer by: every milestone_every owned, milestone_multiplier.</summary>
    public double Multiplier(string id)
    {
        int every = (int)Catalog.Setting("milestone_every");
        if (every <= 0)
            return 1.0;
        return Numbers.Power(Catalog.Setting("milestone_multiplier"), (int)Math.Floor(Count(id) / (double)every));
    }

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

    private void Recompute()
    {
        RateComputations++;
        _rates.Clear();
        _rate = 0.0;
        foreach (ProducerData p in Catalog.Producers)
        {
            double r = p.Rate * Count(p.Id) * Multiplier(p.Id);
            _rates[p.Id] = r;
            _rate += r;
        }
        _dirty = false;
    }

    /// <summary>Glow for one press of Gather.</summary>
    public double TapValue() => Catalog.Setting("tap");

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
        Earn(earned);
        return earned;
    }

    public void Earn(double amount)
    {
        Glow = Math.Min(Glow + amount, Numbers.Max);
    }
}
