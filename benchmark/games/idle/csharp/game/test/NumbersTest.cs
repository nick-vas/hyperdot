namespace Duskhive.Tests;

using System.Globalization;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Numbers: how glow is shown, from a few motes to past a double's 2^53, and the arithmetic behind it.</summary>
[TestSuite]
public class NumbersTest
{
    [TestCase]
    public void Small_numbers_are_whole_or_one_decimal()
    {
        AssertThat(Numbers.Format(0.0)).IsEqual("0");
        AssertThat(Numbers.Format(0.5)).IsEqual("0.5");
        AssertThat(Numbers.Format(7.0)).IsEqual("7");
        AssertThat(Numbers.Format(999.9)).IsEqual("999");
    }

    [TestCase]
    public void Thousands_take_a_suffix_and_three_digits()
    {
        AssertThat(Numbers.Format(1000.0)).IsEqual("1.00K");
        AssertThat(Numbers.Format(12345.0)).IsEqual("12.3K");
        AssertThat(Numbers.Format(999999.0)).IsEqual("999K");
        AssertThat(Numbers.Format(1.5e9)).IsEqual("1.50B");
        AssertThat(Numbers.Format(2.5e12)).IsEqual("2.50T");
    }

    [TestCase]
    public void The_screen_rounds_down()
    {
        AssertThat(Numbers.Format(1999.0)).IsEqual("1.99K");
        AssertThat(Numbers.Format(9.999e6)).IsEqual("9.99M");
    }

    [TestCase]
    public void Decillions_are_the_last_short_name()
    {
        AssertThat(Numbers.Format(1e33)).IsEqual("1.00Dc");
        AssertThat(Numbers.Format(4.2e35)).IsEqual("420Dc");
    }

    [TestCase]
    public void Past_decillions_letters_take_over()
    {
        AssertThat(Numbers.Format(1.5e36)).IsEqual("1.50aa");
        AssertThat(Numbers.Format(1e39)).IsEqual("1.00ab");
        AssertThat(Numbers.Format(1e114)).IsEqual("1.00ba");
    }

    [TestCase]
    public void No_number_prints_in_scientific_notation()
    {
        for (int exponent = 0; exponent < 301; exponent += 7)
        {
            string text = Numbers.Format(double.Parse($"3.7e{exponent}", CultureInfo.InvariantCulture));
            AssertThat(text.Contains("e+") || text.Contains("e-") || text.Contains("E")).OverrideFailureMessage(text).IsFalse();
        }
    }

    [TestCase]
    public void Powers_are_multiplied_out()
    {
        AssertThat(Numbers.Power(1.15, 0)).IsEqual(1.0);
        AssertThat(Numbers.Power(2.0, 10)).IsEqual(1024.0);
        AssertThat(Numbers.Close(Numbers.Power(1.15, 100), 1174313.4507002793, 1e-14)).IsTrue();
        AssertThat(Numbers.Power(2.0, -2)).IsEqual(0.25);
    }

    [TestCase]
    public void Close_is_relative()
    {
        AssertThat(Numbers.Close(1e20, 1e20 + 1e7)).IsTrue();
        AssertThat(Numbers.Close(1e20, 1e20 * (1.0 + 1e-10))).IsFalse();
    }
}
