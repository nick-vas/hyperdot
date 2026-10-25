namespace Lanternfen;

using System;
using Godot;

/// <summary>The panel over a finished duel: won or lost, Next (Finish after the last rival) once won, Rematch, and Back to menu.</summary>
public partial class ResultMenu : CanvasLayer
{
    private bool _won;
    private string _nextKey = "RESULT_NEXT";
    private Label _title = null!;
    private Label _message = null!;
    private Button _next = null!;
    private Button _rematch = null!;
    private Button _menu = null!;

    public event Action? NextPressed;
    public event Action? RematchPressed;
    public event Action? MenuPressed;

    public override void _Ready()
    {
        _title = GetNode<Label>("Box/Title");
        _message = GetNode<Label>("Box/MessageLabel");
        _next = GetNode<Button>("Box/NextButton");
        _rematch = GetNode<Button>("Box/RematchButton");
        _menu = GetNode<Button>("Box/MenuButton");
        Visible = false;
        _next.Pressed += () => NextPressed?.Invoke();
        _rematch.Pressed += () => RematchPressed?.Invoke();
        _menu.Pressed += () => MenuPressed?.Invoke();
        RefreshText();
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            RefreshText();
    }

    private void RefreshText()
    {
        _title.Text = _won ? Tr("RESULT_WON") : Tr("RESULT_LOST");
        _message.Text = _won ? Tr("RESULT_WON_MESSAGE") : Tr("RESULT_LOST_MESSAGE");
        _next.Text = Tr(_nextKey);
        _rematch.Text = Tr("RESULT_REMATCH");
        _menu.Text = Tr("RESULT_MENU");
    }

    /// <summary>nextKey: the Next button's text key; the button shows only after a win.</summary>
    public void Open(bool won, string nextKey)
    {
        _won = won;
        _nextKey = nextKey;
        _next.Visible = won;
        RefreshText();
        Visible = true;
    }

    public void Close()
    {
        Visible = false;
    }
}
