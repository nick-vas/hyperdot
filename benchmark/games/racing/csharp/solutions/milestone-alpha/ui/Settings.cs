namespace Cinderloop;

using System;
using System.Collections.Generic;
using Godot;

/// <summary>
/// Volume, language and the keys. Changes apply at once; Main saves them when the screen closes. A key button waits for
/// the next key pressed (Escape keeps the old one); the gamepad's bindings never change.
/// </summary>
/// <remarks><c>waiting</c> and <c>capture_key</c> keep the names the controls flow uses.</remarks>
public partial class Settings : Control
{
    /// <summary>Each language's own name, the same in every table.</summary>
    private static readonly Dictionary<string, string> LanguageNames = new()
    {
        ["en"] = "LANG_EN",
        ["fr"] = "LANG_FR",
        ["de"] = "LANG_DE",
    };

    private static readonly Dictionary<string, string> ActionKeys = new()
    {
        ["accelerate"] = "CONTROL_ACCELERATE",
        ["brake"] = "CONTROL_BRAKE",
        ["steer_left"] = "CONTROL_LEFT",
        ["steer_right"] = "CONTROL_RIGHT",
    };

    private SaveData? _save;
    private Label _title = null!;
    private Label _volumeLabel = null!;
    private HSlider _volume = null!;
    private Label _languageLabel = null!;
    private HBoxContainer _languages = null!;
    private Label _controlsLabel = null!;
    private GridContainer _controls = null!;
    private Button _back = null!;

    public event Action? Closed;

    /// <summary>The action waiting for its new key, "" when none is.</summary>
    public string waiting { get; private set; } = "";

    public void Setup(SaveData save)
    {
        _save = save;
    }

    public override void _Ready()
    {
        _title = GetNode<Label>("Box/Title");
        _volumeLabel = GetNode<Label>("Box/VolumeLabel");
        _volume = GetNode<HSlider>("Box/VolumeSlider");
        _languageLabel = GetNode<Label>("Box/LanguageLabel");
        _languages = GetNode<HBoxContainer>("Box/Languages");
        _controlsLabel = GetNode<Label>("Box/ControlsLabel");
        _controls = GetNode<GridContainer>("Box/Controls");
        _back = GetNode<Button>("Box/BackButton");
        _save ??= new SaveData();
        _volume.Value = _save.Volume;
        _volume.ValueChanged += OnVolumeChanged;
        // One button per language the game ships, so adding a translation adds its button.
        var locales = new List<string>(TranslationServer.GetLoadedLocales());
        locales.Sort(string.CompareOrdinal);
        foreach (string locale in locales)
        {
            string chosen = locale;
            var button = new Button
            {
                Name = $"{locale.Capitalize()}Button",
                CustomMinimumSize = new Vector2(150, 64),
            };
            button.SetMeta("locale", locale);
            button.Pressed += () => SetLocale(chosen);
            _languages.AddChild(button);
        }
        foreach (string action in Controls.Actions)
        {
            string chosen = action;
            var label = new Label { Name = $"{action.ToPascalCase()}Label" };
            label.AddThemeFontSizeOverride("font_size", 22);
            label.SetMeta("action", action);
            _controls.AddChild(label);
            var button = new Button
            {
                Name = $"{action.ToPascalCase()}Button",
                CustomMinimumSize = new Vector2(180, 56),
            };
            button.SetMeta("action", action);
            button.Pressed += () => BeginRebind(chosen);
            _controls.AddChild(button);
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
        _title.Text = Tr("SETTINGS_TITLE");
        _volumeLabel.Text = Tr("SETTINGS_VOLUME");
        _languageLabel.Text = Tr("SETTINGS_LANGUAGE");
        _controlsLabel.Text = Tr("SETTINGS_CONTROLS");
        _back.Text = Tr("SETTINGS_BACK");
        foreach (Node node in _languages.GetChildren())
        {
            var button = (Button)node;
            string locale = button.GetMeta("locale").AsString();
            button.Text = Tr(LanguageNames.TryGetValue(locale, out string? key) ? key : locale);
        }
        foreach (Node node in _controls.GetChildren())
        {
            string action = node.GetMeta("action").AsString();
            if (node is Button button)
                button.Text = action == waiting ? Tr("SETTINGS_PRESS_KEY") : Controls.Label(action);
            else if (node is Label label)
                label.Text = Tr(ActionKeys[action]);
        }
    }

    public void SetLocale(string locale)
    {
        _save!.Locale = locale;
        TranslationServer.SetLocale(locale);
    }

    public void BeginRebind(string action)
    {
        waiting = action;
        RefreshText();
    }

    /// <summary>The key pressed while an action waits: it becomes the action's key (Escape cancels). Flows call it directly.</summary>
    public void capture_key(int key)
    {
        if (waiting == "")
            return;
        if ((Key)key != Key.Escape)
        {
            Controls.Rebind(waiting, (Key)key);
            _save!.Controls = Controls.ToDict();
        }
        waiting = "";
        RefreshText();
    }

    public override void _Input(InputEvent @event)
    {
        if (waiting == "" || @event is not InputEventKey key || !key.Pressed || key.Echo)
            return;
        capture_key((int)(key.PhysicalKeycode != Key.None ? key.PhysicalKeycode : key.Keycode));
        GetViewport().SetInputAsHandled();
    }

    private void OnVolumeChanged(double value)
    {
        _save!.Volume = value;
        AudioServer.SetBusVolumeDb(0, Mathf.LinearToDb(Mathf.Max((float)value, 0.0001f)));
    }
}
