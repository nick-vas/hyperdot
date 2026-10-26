namespace Wickerdeep;

using System;
using Godot;

/// <summary>The pause menu. It runs while the tree is paused (process mode Always) so Escape and its buttons still work.</summary>
public partial class PauseMenu : CanvasLayer
{
    private static readonly StringName PauseAction = "pause";

    private Button _resume = null!;
    private Button _quit = null!;
    private Label _title = null!;

    public event Action? QuitPressed;

    public override void _Ready()
    {
        _resume = GetNode<Button>("ResumeButton");
        _quit = GetNode<Button>("QuitButton");
        _title = GetNode<Label>("Title");
        Visible = false;
        _resume.Pressed += Close;
        _quit.Pressed += OnQuit;
        RefreshText();
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            RefreshText();
    }

    private void RefreshText()
    {
        _title.Text = Tr("PAUSE_TITLE");
        _resume.Text = Tr("PAUSE_RESUME");
        _quit.Text = Tr("PAUSE_QUIT");
    }

    public override void _UnhandledInput(InputEvent @event)
    {
        if (@event.IsActionPressed(PauseAction))
        {
            if (Visible)
                Close();
            else
                Open();
            GetViewport().SetInputAsHandled();
        }
    }

    public void Open()
    {
        Visible = true;
        GetTree().Paused = true;
    }

    public void Close()
    {
        Visible = false;
        GetTree().Paused = false;
    }

    private void OnQuit()
    {
        Close();
        QuitPressed?.Invoke();
    }

    public override void _ExitTree()
    {
        // A game freed while paused must not leave the whole tree paused behind it.
        if (Visible)
            GetTree().Paused = false;
    }
}
