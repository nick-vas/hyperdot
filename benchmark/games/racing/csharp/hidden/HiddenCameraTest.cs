namespace Cinderloop.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the alpha's fix-bug: the chase camera eases the same at any frame rate, never jumps past where it
/// is heading when a frame takes long, still eases (it is not bolted to the car), looks ahead, and keeps the car on the
/// screen through a hairpin taken flat out with hitches.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenCameraTest
{
    /// <summary>A step inside the camera's limit on how far behind it may fall, so only its easing moves it.</summary>
    private static readonly Vector2 Jump = new(200, 0);

    private readonly List<ChaseCamera> _cameras = new();

    [AfterTest]
    public void FreeCameras()
    {
        foreach (ChaseCamera camera in _cameras)
            camera.Free();
        _cameras.Clear();
    }

    private ChaseCamera MakeCamera()
    {
        var camera = new ChaseCamera { Zoom = new Vector2(0.8f, 0.8f) };
        ((SceneTree)Engine.GetMainLoop()).Root.AddChild(camera);
        _cameras.Add(camera);
        camera.ResetTo(Vector2.Zero);
        return camera;
    }

    /// <summary>How far the view still is from a car that jumped 200 px and then stood still, after the given seconds at an fps.</summary>
    private float LeftAfter(int fps, double seconds)
    {
        ChaseCamera camera = MakeCamera();
        int frames = Maths.RoundI(seconds * fps);
        for (int i = 0; i < frames; i++)
            camera.Follow(Jump, Vector2.Zero, 1.0 / fps);
        return camera.Focus.DistanceTo(Jump);
    }

    [TestCase]
    public void Hidden_the_view_eases_the_same_at_any_frame_rate()
    {
        foreach (double seconds in new[] { 1.0 / 3.0, 0.5 })
        {
            float at60 = LeftAfter(60, seconds);
            AssertThat(at60).OverrideFailureMessage($"still easing after {seconds:F2} s").IsGreater(1f);
            foreach (int fps in new[] { 30, 144 })
                AssertThat(LeftAfter(fps, seconds)).OverrideFailureMessage($"{fps} fps against 60 after {seconds:F2} s").IsEqualApprox(at60, 0.5f);
        }
    }

    [TestCase]
    public void Hidden_a_long_frame_never_overshoots()
    {
        foreach (double frame in new[] { 0.1, 0.25, 0.5 })
        {
            ChaseCamera camera = MakeCamera();
            Vector2 before = camera.Focus;
            camera.Follow(Jump, Vector2.Zero, frame);
            Vector2 moved = camera.Focus - before;
            AssertThat(moved.X).OverrideFailureMessage($"a {frame:F2} s frame moves towards the car").IsGreater(0f);
            AssertThat(moved.X).OverrideFailureMessage($"a {frame:F2} s frame stops short of the car").IsLess(Jump.X);
            AssertThat(moved.Y).IsEqualApprox(0f, 0.001f);
        }
    }

    [TestCase]
    public void Hidden_the_view_is_not_bolted_to_the_car()
    {
        ChaseCamera camera = MakeCamera();
        camera.Follow(Jump, Vector2.Zero, 1.0 / 60.0);
        AssertThat(camera.Focus.X).OverrideFailureMessage("one frame covers less than half the jump").IsLess(Jump.X / 2f);
    }

    [TestCase]
    public void Hidden_the_view_looks_ahead_at_speed()
    {
        ChaseCamera camera = MakeCamera();
        Vector2 car = Vector2.Zero;
        for (int i = 0; i < 120; i++)
        {
            car += new Vector2(0, -700) / 60f;
            camera.Follow(car, new Vector2(0, -700), 1.0 / 60.0);
        }
        AssertThat(camera.Focus.Y).OverrideFailureMessage("the view is ahead of a car going up").IsLess(car.Y - 40f);
    }

    [TestCase]
    public void Hidden_a_hairpin_flat_out_keeps_the_car_on_screen()
    {
        foreach (int fps in new[] { 20, 60, 144 })
        {
            ChaseCamera camera = MakeCamera();
            Vector2 half = new Vector2(1280, 720) / camera.Zoom / 2f - new Vector2(40, 40);
            Vector2 car = Vector2.Zero;
            double t = 0.0;
            int frame = 0;
            while (t < 4.0)
            {
                // Every twentieth frame is a hitch of a sixth of a second.
                double dt = frame % 20 != 19 ? 1.0 / fps : 1.0 / 6.0;
                frame += 1;
                t += dt;
                Vector2 velocity = t < 1.0 ? new Vector2(0, -800) : new Vector2(0, 800);
                car += velocity * (float)dt;
                camera.Follow(car, velocity, dt);
                Vector2 off = (car - camera.Focus).Abs();
                AssertThat(off.X <= half.X && off.Y <= half.Y).OverrideFailureMessage($"{fps} fps, {t:F2} s: the car is {off} from the middle").IsTrue();
            }
        }
    }
}
