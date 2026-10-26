namespace Bramblegate;

using System.Collections.Generic;
using Godot;

/// <summary>
/// The busiest field the game can show, for the kit's bench: a wide maze of towers, a swarm of pests kept at Pests on
/// the field and every shot in the air, drawn by the game's own Field.
/// hyperdot.ps1 bench -Scene res://bench/swarm.tscn -BudgetMs 16.6
/// </summary>
public partial class Swarm : Node2D
{
    public const int Pests = 200;
    private static readonly string[] Rows =
    {
        "................",
        "................",
        "................",
        "................",
        "S..............G",
        "................",
        "................",
        "................",
        "................",
    };
    private static readonly string[] Kinds = { "thorn", "puff", "acorn" };
    private static readonly string[] PestKinds = { "aphid", "beetle", "moth" };

    private Field _field = null!;

    public Battle Battle { get; private set; } = null!;

    public override void _Ready()
    {
        _field = GetNode<Field>("Field");
        Battle = Battle.Custom(Catalog.FromFiles(), Rows, 100000, 100000, new List<WaveRow>(), 1, "swarm");
        // Walls with a gap at alternate ends: the longest way across the field, lined with towers on both sides.
        int n = 0;
        for (int x = 2; x < 15; x += 3)
        {
            for (int y = 0; y < 9; y++)
            {
                int gap = (x - 2) % 6 == 0 ? 8 : 0;
                if (y != gap && Battle.Place(Kinds[n % Kinds.Length], new Vector2I(x, y)))
                    n += 1;
            }
        }
        _field.ShowBattle(Battle);
    }

    public override void _PhysicsProcess(double delta)
    {
        while (Battle.Enemies.Count < Pests)
        {
            Enemy pest = Battle.SpawnAt(PestKinds[Battle.Enemies.Count % PestKinds.Length], Battle.Map.Gate);
            pest.Hp = 1000000;
        }
        Battle.Step();
        _field.QueueRedraw();
    }
}
