namespace Duskhive;

using System;
using System.Collections.Generic;
using Godot;

/// <summary>Volume and language. Changes apply at once; Main saves them when the screen closes.</summary>
public partial class Settings : Control
{
    /// <summary>Each language's own name, the same in every table.</summary>
    private static readonly Dictionary<string, string> LanguageNames = new()
    {
        ["en"] = "LANG_EN",
        ["de"] = "LANG_DE",
        ["fr"] = "LANG_FR",
    };

    private SaveData? _save;
    private Label _title = null!;
    private Label _volumeLabel = null!;
    private HSlider _volume = null!;
    private Label _languageLabel = null!;
    private HBoxContainer _languages = null!;
    private Button _back = null!;
    private Label _version = null!;

    public event Action? Closed;

    public void Setup(SaveData save)
    {
        _save = save;
    }

    public override void _Ready()
    {
        _title = GetNode<Label>("Safe/Box/Title");
        _volumeLabel = GetNode<Label>("Safe/Box/VolumeLabel");
        _volume = GetNode<HSlider>("Safe/Box/VolumeSlider");
        _languageLabel = GetNode<Label>("Safe/Box/LanguageLabel");
        _languages = GetNode<HBoxContainer>("Safe/Box/Languages");
        _back = GetNode<Button>("Safe/Box/BackButton");
        _version = GetNode<Label>("Safe/Box/VersionLabel");
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
                CustomMinimumSize = new Vector2(0, 88),
                SizeFlagsHorizontal = SizeFlags.ExpandFill,
            };
            button.AddThemeFontSizeOverride("font_size", 26);
            button.SetMeta("locale", locale);
            button.Pressed += () => SetLocale(chosen);
            _languages.AddChild(button);
        }
        _back.Pressed += Hide;
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
        _back.Text = Tr("SETTINGS_BACK");
        _version.Text = TextFormat.Fill(Tr("SETTINGS_VERSION"), ProjectSettings.GetSetting("application/config/version", "").AsString());
        foreach (Node node in _languages.GetChildren())
        {
            var button = (Button)node;
            string locale = button.GetMeta("locale").AsString();
            button.Text = Tr(LanguageNames.TryGetValue(locale, out string? key) ? key : locale);
        }
    }

    public void SetLocale(string locale)
    {
        _save!.Locale = locale;
        TranslationServer.SetLocale(locale);
    }

    private void OnVolumeChanged(double value)
    {
        _save!.Volume = value;
        AudioServer.SetBusVolumeDb(0, Mathf.LinearToDb(Mathf.Max((float)value, 0.0001f)));
    }
}
