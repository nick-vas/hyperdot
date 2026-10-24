namespace Lanternfen;

using System;
using Godot;

/// <summary>The ladder of rivals, one button each: open once the rival before is beaten, with the wins against a beaten one.</summary>
public partial class RivalSelect : Control
{
    private Rivals? _rivals;
    private SaveData? _save;
    private Label _title = null!;
    private GridContainer _grid = null!;
    private Button _back = null!;

    public event Action<int>? RivalChosen;
    public event Action? Closed;

    public void Setup(Rivals rivals, SaveData save)
    {
        _rivals = rivals;
        _save = save;
    }

    public override void _Ready()
    {
        _title = GetNode<Label>("Box/Title");
        _grid = GetNode<GridContainer>("Box/Grid");
        _back = GetNode<Button>("Box/BackButton");
        _rivals ??= Rivals.FromFiles();
        _save ??= new SaveData();
        for (int id = 1; id <= _rivals.Count; id++)
        {
            int chosen = id;
            var button = new Button
            {
                Name = $"Rival{id}Button",
                CustomMinimumSize = new Vector2(320, 88),
                Disabled = !Ladder.IsUnlocked(_save, id),
            };
            button.AddThemeFontSizeOverride("font_size", 22);
            button.Pressed += () => RivalChosen?.Invoke(chosen);
            _grid.AddChild(button);
        }
        _back.Pressed += () => Closed?.Invoke();
        RefreshText();
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            RefreshText();
    }

    private void RefreshText()
    {
        _title.Text = Tr("SELECT_TITLE");
        _back.Text = Tr("SELECT_BACK");
        for (int id = 1; id <= _grid.GetChildCount(); id++)
        {
            var button = (Button)_grid.GetChild(id - 1);
            button.Text = TextFormat.Fill(Tr("SELECT_RIVAL"), id, Tr(_rivals!.Rival(id)?.Name ?? ""));
            int wins = Ladder.Wins(_save!, id);
            if (wins > 0)
                button.Text += "  " + TextFormat.Fill(Tr("SELECT_WINS"), wins);
        }
    }
}
