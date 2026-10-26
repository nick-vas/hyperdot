namespace SaltmereCrossing.Tests;

using System.Collections.Generic;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Conditions: a choice's needs in the criteria grammar.</summary>
[TestSuite]
public class ConditionsTest
{
    private static Dictionary<string, int> Flags(params (string Key, int Value)[] pairs)
    {
        var flags = new Dictionary<string, int>();
        foreach ((string key, int value) in pairs)
            flags[key] = value;
        return flags;
    }

    [TestCase]
    public void Empty_needs_always_hold()
    {
        AssertThat(Conditions.Holds("", Flags())).IsTrue();
        AssertThat(Conditions.Holds("  ", Flags(("trust", 3)))).IsTrue();
    }

    [TestCase]
    public void Not_holds_only_on_zero_or_missing()
    {
        AssertThat(Conditions.Holds("!afraid", Flags())).IsTrue();
        AssertThat(Conditions.Holds("!afraid", Flags(("afraid", 0)))).IsTrue();
        AssertThat(Conditions.Holds("!afraid", Flags(("afraid", 1)))).IsFalse();
    }

    [TestCase]
    public void At_least_holds_on_the_bound_and_above()
    {
        AssertThat(Conditions.Holds("trust>=2", Flags(("trust", 1)))).IsFalse();
        AssertThat(Conditions.Holds("trust>=2", Flags(("trust", 2)))).IsTrue();
        AssertThat(Conditions.Holds("trust>=2", Flags(("trust", 5)))).IsTrue();
    }

    [TestCase]
    public void Each_operator()
    {
        Dictionary<string, int> flags = Flags(("trust", 2));
        AssertThat(Conditions.Holds("trust=2", flags)).IsTrue();
        AssertThat(Conditions.Holds("trust<2", flags)).IsFalse();
        AssertThat(Conditions.Holds("trust<=2", flags)).IsTrue();
        AssertThat(Conditions.Holds("trust>2", flags)).IsFalse();
        AssertThat(Conditions.Holds("trust>1", flags)).IsTrue();
    }

    [TestCase]
    public void Every_criterion_must_hold()
    {
        AssertThat(Conditions.Holds("trust>=2;!afraid", Flags(("trust", 2), ("afraid", 0)))).IsTrue();
        AssertThat(Conditions.Holds("trust>=2;!afraid", Flags(("trust", 2), ("afraid", 1)))).IsFalse();
        AssertThat(Conditions.Holds("trust>=2; !afraid", Flags(("trust", 1), ("afraid", 0)))).IsFalse();
    }

    [TestCase]
    public void Keys_lists_the_flags_read()
    {
        AssertThat(Conditions.Keys("trust>=2;!afraid")).ContainsExactly("trust", "afraid");
        AssertThat(Conditions.Parse("lied=1")[0]).IsEqual(new Criterion("lied", "=", 1));
    }
}
