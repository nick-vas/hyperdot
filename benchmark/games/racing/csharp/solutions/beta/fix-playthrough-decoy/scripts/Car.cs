namespace Cinderloop;

using System;
using Godot;
using static Cinderloop.Maths;

/// <summary>Where a car is, which way it points and how fast it goes: where a car or a ghost starts.</summary>
public readonly record struct CarState(Vector2 Position, double Heading, double Speed);

/// <summary>
/// One car's handling, stepped once a physics tick by Race: throttle and brake along the heading, steering that needs
/// speed, drag that is higher off the road. Every rate is per second and every step uses its own dt, so a lap takes
/// the same time at any tick rate; nothing here reads the clock or a random generator, so the same inputs from the same
/// state drive the same lap.
/// </summary>
/// <remarks>
/// Scalars are doubles and positions Godot's float vectors, as in the GDScript version, so both give the same lap to the
/// last bit: a scalar meets a vector only as a float.
/// </remarks>
public sealed class Car
{
    /// <summary>Speed gained per second at full throttle, in pixels a second.</summary>
    public const double Accel = 640.0;
    /// <summary>The share of speed lost per second on the road and on the grass: top speeds of Accel / Drag.</summary>
    public const double Drag = 0.8;
    public const double GrassDrag = 3.2;
    /// <summary>Speed lost per second while braking, until the car stands still.</summary>
    public const double Brake = 1000.0;
    public const double ReverseAccel = 320.0;
    public const double ReverseMax = 160.0;
    /// <summary>The fastest turn at full lock, in radians a second, reached once the car moves at TurnSpeed.</summary>
    public const double TurnRate = 2.6;
    public const double TurnSpeed = 140.0;
    /// <summary>The sideways acceleration the tyres hold: above Grip / speed radians a second the car cannot turn tighter.</summary>
    public const double Grip = 1300.0;
    public const double Radius = 14.0;
    /// <summary>The physics tick the handling is tuned at.</summary>
    public const double Tick = 1.0 / 120.0;

    public Vector2 Position { get; set; }
    /// <summary>Radians; 0 points along +x.</summary>
    public double Heading { get; set; }
    /// <summary>Pixels a second along the heading; negative in reverse.</summary>
    public double Speed { get; set; }
    public bool OnRoad { get; private set; } = true;
    /// <summary>The track segment the car is on, kept by Race so the next lookup starts there.</summary>
    public int Index { get; set; }

    public static Car At(CarState state) => new() { Position = state.Position, Heading = state.Heading, Speed = state.Speed };

    public CarState State() => new(Position, Heading, Speed);

    public Vector2 Forward() => Vector2.FromAngle((float)Heading);

    public Vector2 Velocity() => Forward() * (float)Speed;

    /// <summary>throttle: 1 full throttle, -1 full brake (reverse once stopped); steer: -1 full left, 1 full right.</summary>
    public void Step(double throttle, double steer, double dt, bool road = true)
    {
        OnRoad = road;
        throttle = ClampF(throttle, -1.0, 1.0);
        steer = ClampF(steer, -1.0, 1.0);
        Turn(steer, dt);
        if (throttle >= 0.0 || Speed <= 0.0)
        {
            double push = throttle >= 0.0 ? Accel * throttle : ReverseAccel * throttle;
            Speed += push * dt;
        }
        else
        {
            Speed = MaxF(Speed + Brake * throttle * dt, 0.0);
        }
        // Drag taken implicitly, speed / (1 + drag * dt): stable at any step, and the top speed is exactly Accel / Drag at
        // every tick rate. (Exp() would be smoother, but it comes from each OS's C library, and replays must not drift.)
        double drag = road ? Drag : GrassDrag;
        Speed /= 1.0 + drag * Tick;
        Speed = MaxF(Speed, -ReverseMax);
        Position += Forward() * (float)Speed * (float)dt;
    }

    private void Turn(double steer, double dt)
    {
        double moving = Math.Abs(Speed);
        if (moving < 0.001)
            return;
        double rate = TurnRate * MinF(moving / TurnSpeed, 1.0);
        rate = MinF(rate, Grip / moving);
        // Reversing turns the other way, as a real car's nose does.
        Heading = WrapF(Heading + steer * rate * SignF(Speed) * dt, -Math.PI, Math.PI);
    }
}
