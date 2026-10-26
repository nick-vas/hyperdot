namespace Cinderloop.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>ChaseCamera: it starts on the car, catches up with it, and looks ahead the way the car goes.</summary>
[TestSuite]
[RequireGodotRuntime]
public class CameraTest
{
    private ChaseCamera _camera = null!;

    [BeforeTest]
    public void Make()
    {
        _camera = new ChaseCamera();
        ((SceneTree)Engine.GetMainLoop()).Root.AddChild(_camera);
        _camera.ResetTo(new Vector2(100, 50));
    }

    [AfterTest]
    public void FreeCamera()
    {
        _camera.Free();
    }

    [TestCase]
    public void A_reset_centres_the_view_on_the_car()
    {
        AssertThat(_camera.Focus).IsEqual(new Vector2(100, 50));
        AssertThat(_camera.Position).IsEqual(new Vector2(100, 50));
    }

    [TestCase]
    public void The_view_catches_up_with_a_car_that_stopped_elsewhere()
    {
        for (int i = 0; i < 120; i++)
            _camera.Follow(new Vector2(300, 50), Vector2.Zero, 1.0 / 60.0);
        AssertThat(_camera.Focus.DistanceTo(new Vector2(300, 50))).IsEqualApprox(0f, 1f);
    }

    [TestCase]
    public void The_view_looks_ahead_of_a_moving_car()
    {
        var car = new Vector2(100, 50);
        for (int i = 0; i < 180; i++)
        {
            car += new Vector2(400, 0) / 60f;
            _camera.Follow(car, new Vector2(400, 0), 1.0 / 60.0);
        }
        AssertThat(_camera.Focus.X).OverrideFailureMessage("ahead of the car").IsGreater(car.X + 30f);
        AssertThat(_camera.Focus.Y).IsEqualApprox(car.Y, 1f);
    }
}
