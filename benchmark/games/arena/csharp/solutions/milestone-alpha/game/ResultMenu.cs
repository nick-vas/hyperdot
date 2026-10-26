namespace Glimmerpit;

using System;
using Godot;

/// <summary>
/// The panel over a finished match: won or lost, who won by how much, Rematch (not for a joined player, whose host
/// decides) and Back to menu.
/// </summary>
public partial class ResultMenu : CanvasLayer
{
    private bool _won;
    private int _winner = 1;
    private int _score;
    private int _second;

    private Label _title = null!;
    private Label _message = null!;
    private Button _rematch = null!;
    private Button _menu = null!;

    public event Action? RematchPressed;
    public event Action? MenuPressed;

    public override void _Ready()
    {
        _title = GetNode<Label>("Box/Title");
        _message = GetNode<Label>("Box/MessageLabel");
        _rematch = GetNode<Button>("Box/RematchButton");
        _menu = GetNode<Button>("Box/MenuButton");
        Visible = false;
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
        _message.Text = TextFormat.Fill(Tr("RESULT_MESSAGE"), _winner, _score, _second);
        _rematch.Text = Tr("RESULT_REMATCH");
        _menu.Text = Tr("RESULT_MENU");
    }

    /// <summary>winner: the winning player's number (slot + 1); canRematch: false for a joined player.</summary>
    public void Open(bool won, int winner, int score, int second, bool canRematch)
    {
        _won = won;
        _winner = winner;
        _score = score;
        _second = second;
        _rematch.Visible = canRematch;
        RefreshText();
        Visible = true;
    }

    public void Close()
    {
        Visible = false;
    }
}
