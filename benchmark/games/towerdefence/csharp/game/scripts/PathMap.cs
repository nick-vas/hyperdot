namespace Bramblegate;

using System.Collections.Generic;
using Godot;

/// <summary>
/// The field as a grid of cells: rocks and towers block, every other cell is open. Pests walk the shortest way from the
/// gate (where they come in) to the seed store (where they leak), found by AStarGrid2D on four neighbours. The map only
/// knows cells; Battle decides what may be built where.
/// </summary>
public sealed class PathMap
{
    public const char RockTile = '#';
    public const char GateTile = 'S';
    public const char StoreTile = 'G';

    private readonly HashSet<Vector2I> _rocks = new();
    private readonly HashSet<Vector2I> _towers = new();
    private readonly AStarGrid2D _astar = new();

    public Vector2I Size { get; private set; }
    public Vector2I Gate { get; private set; }
    public Vector2I Store { get; private set; }

    /// <summary>Every path search the map ran, previews included: the performance tests read it.</summary>
    public int PathQueries { get; private set; }

    /// <summary>The way from the gate to the store as the map stands, the gate first; empty when there is none.</summary>
    public List<Vector2I> Route { get; private set; } = new();

    /// <summary>A map from rows of text: "." open, "#" rock, "S" the gate, "G" the store.</summary>
    public static PathMap FromRows(IReadOnlyList<string> rows)
    {
        var map = new PathMap { Size = new Vector2I(rows[0].Length, rows.Count) };
        map._astar.Region = new Rect2I(Vector2I.Zero, map.Size);
        map._astar.CellSize = Vector2.One;
        map._astar.DiagonalMode = AStarGrid2D.DiagonalModeEnum.Never;
        map._astar.DefaultComputeHeuristic = AStarGrid2D.Heuristic.Manhattan;
        map._astar.DefaultEstimateHeuristic = AStarGrid2D.Heuristic.Manhattan;
        map._astar.Update();
        for (int y = 0; y < rows.Count; y++)
        {
            string row = rows[y];
            for (int x = 0; x < row.Length; x++)
            {
                var cell = new Vector2I(x, y);
                switch (row[x])
                {
                    case RockTile:
                        map._rocks.Add(cell);
                        map._astar.SetPointSolid(cell, true);
                        break;
                    case GateTile:
                        map.Gate = cell;
                        break;
                    case StoreTile:
                        map.Store = cell;
                        break;
                }
            }
        }
        map.Route = map.PathFrom(map.Gate);
        return map;
    }

    public bool InBounds(Vector2I cell) => cell.X >= 0 && cell.Y >= 0 && cell.X < Size.X && cell.Y < Size.Y;

    public bool IsRock(Vector2I cell) => _rocks.Contains(cell);

    /// <summary>A pest may stand on it: inside the map, no rock and no tower.</summary>
    public bool IsOpen(Vector2I cell) => InBounds(cell) && !_rocks.Contains(cell) && !_towers.Contains(cell);

    /// <summary>A tower may stand on it, as far as the map goes: open, and neither the gate nor the store.</summary>
    public bool IsBuildable(Vector2I cell) => IsOpen(cell) && cell != Gate && cell != Store;

    /// <summary>The shortest way from a cell to the store, that cell first; empty when the store cannot be reached from it.</summary>
    public List<Vector2I> PathFrom(Vector2I cell)
    {
        PathQueries += 1;
        if (!IsOpen(cell))
            return new List<Vector2I>();
        return new List<Vector2I>(_astar.GetIdPath(cell, Store));
    }

    public void SetTower(Vector2I cell, bool standing)
    {
        if (standing)
            _towers.Add(cell);
        else
            _towers.Remove(cell);
        _astar.SetPointSolid(cell, standing || _rocks.Contains(cell));
        Route = PathFrom(Gate);
    }

    /// <summary>Whether a tower on this cell would leave the gate, or any of the cells pests are heading to, with no way to the store.</summary>
    public bool Blocks(Vector2I cell, IEnumerable<Vector2I> fromCells)
    {
        bool wasSolid = _astar.IsPointSolid(cell);
        _astar.SetPointSolid(cell, true);
        _towers.Add(cell);
        bool blocked = false;
        var tried = new HashSet<Vector2I>();
        var starts = new List<Vector2I> { Gate };
        starts.AddRange(fromCells);
        foreach (Vector2I start in starts)
        {
            if (!tried.Add(start))
                continue;
            if (PathFrom(start).Count == 0)
            {
                blocked = true;
                break;
            }
        }
        _towers.Remove(cell);
        _astar.SetPointSolid(cell, wasSolid);
        return blocked;
    }

    /// <summary>The route as it would be with a tower on this cell (empty when the tower would block it), for the bot's choices.</summary>
    public List<Vector2I> PreviewRoute(Vector2I cell)
    {
        bool wasSolid = _astar.IsPointSolid(cell);
        _astar.SetPointSolid(cell, true);
        _towers.Add(cell);
        List<Vector2I> preview = PathFrom(Gate);
        _towers.Remove(cell);
        _astar.SetPointSolid(cell, wasSolid);
        return preview;
    }
}
