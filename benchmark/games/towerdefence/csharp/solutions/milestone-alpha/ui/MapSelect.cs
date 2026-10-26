namespace Bramblegate;

using System;
using Godot;

/// <summary>The campaign's maps, one button each: open once the map before is cleared, with the stars of a cleared one.</summary>
public partial class MapSelect : Control
{
    private Catalog? _catalog;
    private SaveData? _save;
    private Label _title = null!;
    private GridContainer _grid = null!;
    private Button _back = null!;

    public event Action<int>? MapChosen;
    public event Action? Closed;

    public void Setup(Catalog catalog, SaveData save)
    {
        _catalog = catalog;
        _save = save;
    }

    public override void _Ready()
    {
        _title = GetNode<Label>("Box/Title");
        _grid = GetNode<GridContainer>("Box/Grid");
        _back = GetNode<Button>("Box/BackButton");
        _catalog ??= Catalog.FromFiles();
        _save ??= new SaveData();
        for (int index = 1; index <= _catalog.MapCount; index++)
        {
            int chosen = index;
            var button = new Button
            {
                Name = $"Map{index}Button",
                CustomMinimumSize = new Vector2(520, 88),
                Disabled = !Progress.IsUnlocked(_save, _catalog, index),
            };
            button.AddThemeFontSizeOverride("font_size", 24);
            button.Pressed += () => MapChosen?.Invoke(chosen);
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
        for (int index = 1; index <= _grid.GetChildCount(); index++)
        {
            var button = (Button)_grid.GetChild(index - 1);
            MapRow row = _catalog!.MapAt(index)!;
            button.Text = TextFormat.Fill(Tr("SELECT_MAP"), index, Tr(row.Name));
            int stars = Progress.Stars(_save!, row.Id);
            if (stars > 0)
                button.Text += "  " + TextFormat.Fill(Tr("SELECT_STARS"), stars);
        }
    }
}
