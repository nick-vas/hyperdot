namespace Bramblegate;

using System;
using Godot;

/// <summary>
/// The panel over a finished map: cleared (with its stars) or lost, Next (Finish after the last map) once cleared, Retry,
/// and Back to menu.
/// </summary>
public partial class ResultMenu : CanvasLayer
{
    private bool _won;
    private int _stars;
    private string _nextKey = "RESULT_NEXT";
    private Label _title = null!;
    private Label _message = null!;
    private Button _next = null!;
    private Button _retry = null!;
    private Button _menu = null!;

    public event Action? NextPressed;
    public event Action? RetryPressed;
    public event Action? MenuPressed;

    public override void _Ready()
    {
        _title = GetNode<Label>("Box/Title");
        _message = GetNode<Label>("Box/MessageLabel");
        _next = GetNode<Button>("Box/NextButton");
        _retry = GetNode<Button>("Box/RetryButton");
        _menu = GetNode<Button>("Box/MenuButton");
        Visible = false;
        _next.Pressed += () => NextPressed?.Invoke();
        _retry.Pressed += () => RetryPressed?.Invoke();
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
        _message.Text = _won ? TextFormat.Fill(Tr("RESULT_WON_MESSAGE"), _stars) : Tr("RESULT_LOST_MESSAGE");
        _next.Text = Tr(_nextKey);
        _retry.Text = Tr("RESULT_RETRY");
        _menu.Text = Tr("RESULT_MENU");
    }

    /// <summary>stars: what the cleared map earned; nextKey: the Next button's text key. The button shows only after a win.</summary>
    public void Open(bool won, int stars, string nextKey)
    {
        _won = won;
        _stars = stars;
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
