namespace Cinderloop;

using System;
using Godot;

/// <summary>The panel at the end of a race: the place, the best lap, and Next (when the place opens the next track), Retry and Menu.</summary>
public partial class ResultMenu : CanvasLayer
{
    private int _place;
    private int _cars;
    private int _bestMs;
    private Label _title = null!;
    private Label _placeLabel = null!;
    private Label _timeLabel = null!;
    private Button _next = null!;
    private Button _retry = null!;
    private Button _menu = null!;

    public event Action? NextPressed;
    public event Action? RetryPressed;
    public event Action? MenuPressed;

    public override void _Ready()
    {
        _title = GetNode<Label>("Box/Title");
        _placeLabel = GetNode<Label>("Box/PlaceLabel");
        _timeLabel = GetNode<Label>("Box/TimeLabel");
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

    public void Open(int place, int cars, int bestMs, bool canGoOn)
    {
        _place = place;
        _cars = cars;
        _bestMs = bestMs;
        _next.Visible = canGoOn;
        Visible = true;
        RefreshText();
    }

    public void Close()
    {
        Visible = false;
    }

    private void RefreshText()
    {
        _title.Text = Tr("RESULT_TITLE");
        _placeLabel.Text = TextFormat.Fill(Tr("RESULT_PLACE"), _place, _cars);
        _timeLabel.Text = TextFormat.Fill(Tr("RESULT_BEST"), Race.FormatMs(_bestMs));
        _next.Text = Tr("RESULT_NEXT");
        _retry.Text = Tr("RESULT_RETRY");
        _menu.Text = Tr("RESULT_MENU");
    }
}
