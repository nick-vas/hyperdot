namespace Cinderloop.Tests;

using System;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Car: throttle and top speed, braking and reverse, steering that needs speed and the grass.</summary>
[TestSuite]
public class CarTest
{
    private const double Dt = 1.0 / 60.0;

    private static void Drive(Car car, double throttle, double steer, double seconds, int rate = 60, bool road = true)
    {
        int ticks = Maths.RoundI(seconds * rate);
        for (int i = 0; i < ticks; i++)
            car.Step(throttle, steer, 1.0 / rate, road);
    }

    [TestCase]
    public void Full_throttle_speeds_the_car_up_along_its_heading()
    {
        var car = new Car { Heading = Math.PI / 2.0 };
        Drive(car, 1.0, 0.0, 1.0);
        AssertThat(car.Speed).IsGreater(400.0);
        AssertThat(car.Position.X).IsEqualApprox(0f, 0.01f);
        AssertThat(car.Position.Y).IsGreater(200f);
    }

    [TestCase]
    public void Top_speed_is_acceleration_over_drag()
    {
        var car = new Car();
        Drive(car, 1.0, 0.0, 12.0);
        AssertThat(car.Speed).IsEqualApprox(Car.Accel / Car.Drag, 15.0);
    }

    [TestCase]
    public void Half_throttle_tops_out_at_half_the_speed()
    {
        var car = new Car();
        Drive(car, 0.5, 0.0, 12.0);
        AssertThat(car.Speed).IsEqualApprox(Car.Accel / Car.Drag / 2.0, 10.0);
    }

    [TestCase]
    public void Coasting_slows_the_car_down()
    {
        var car = new Car { Speed = 500.0 };
        Drive(car, 0.0, 0.0, 1.0);
        // About Drag of the speed goes each second: 500 px/s coasts down to about 225 in one.
        AssertThat(car.Speed).IsBetween(200.0, 250.0);
    }

    [TestCase]
    public void Braking_stops_the_car_without_reversing_in_the_same_tick()
    {
        var car = new Car { Speed = 100.0 };
        int ticks = 0;
        while (car.Speed > 0.0 && ticks < 60)
        {
            car.Step(-1.0, 0.0, Dt);
            ticks += 1;
            AssertThat(car.Speed >= 0.0).OverrideFailureMessage("never below zero while braking from forward").IsTrue();
        }
        AssertThat(car.Speed).IsEqual(0.0);
        AssertThat(ticks).OverrideFailureMessage("a tenth of a second from 100 px/s").IsLess(10);
    }

    [TestCase]
    public void Holding_the_brake_once_stopped_reverses_up_to_the_limit()
    {
        var car = new Car();
        Drive(car, -1.0, 0.0, 5.0);
        AssertThat(car.Speed).IsEqualApprox(-Car.ReverseMax, 0.01);
    }

    [TestCase]
    public void A_standing_car_does_not_turn()
    {
        var car = new Car();
        Drive(car, 0.0, 1.0, 1.0);
        AssertThat(car.Heading).IsEqual(0.0);
    }

    [TestCase]
    public void A_slow_car_turns_less_than_a_quick_one()
    {
        var car = new Car { Speed = Car.TurnSpeed / 4.0 };
        car.Step(0.0, 1.0, Dt);
        AssertThat(car.Heading).IsEqualApprox(Car.TurnRate / 4.0 * Dt, 0.0005);
    }

    [TestCase]
    public void Steering_right_turns_clockwise_on_screen()
    {
        var car = new Car { Speed = 300.0 };
        Drive(car, 0.0, 1.0, 0.25);
        AssertThat(car.Heading).IsGreater(0.3);
    }

    [TestCase]
    public void Reversing_turns_the_nose_the_other_way()
    {
        var car = new Car { Speed = -150.0 };
        Drive(car, 0.0, 1.0, 0.25);
        AssertThat(car.Heading).IsLess(-0.1);
    }

    [TestCase]
    public void Grip_limits_the_turn_at_speed()
    {
        var slow = new Car { Speed = 200.0 };
        var fast = new Car { Speed = 700.0 };
        slow.Step(0.0, 1.0, Dt);
        fast.Step(0.0, 1.0, Dt);
        AssertThat(slow.Heading).IsEqualApprox(Car.TurnRate * Dt, 0.0001);
        AssertThat(fast.Heading).OverrideFailureMessage("full lock at 700 px/s turns less than at 200").IsLess(slow.Heading);
    }

    [TestCase]
    public void The_grass_holds_the_car_back()
    {
        var road = new Car();
        var grass = new Car();
        Drive(road, 1.0, 0.0, 6.0);
        Drive(grass, 1.0, 0.0, 6.0, 60, false);
        AssertThat(grass.Speed).IsEqualApprox(Car.Accel / Car.GrassDrag, 10.0);
        AssertThat(grass.Speed).IsLess(road.Speed / 2.0);
    }
}
