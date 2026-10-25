namespace Wickerdeep;

using System;
using System.Collections.Generic;
using System.Text;
using Godot;

/// <summary>An enemy to place: its kind and its cell.</summary>
public readonly record struct Spawn(string Kind, Vector2I Cell);

/// <summary>
/// One floor of the crypt, generated from a seed: walls and floor on a grid, rectangular rooms joined by corridors, where
/// the wick starts, the stairs down and where each enemy waits. Pure data, built before any node: the same seed and
/// floor give the same dungeon on every machine, and in the GDScript version too (the engine's RandomNumberGenerator,
/// its draws in the same order), so a seed from a bug report rebuilds the floor and a test can sweep hundreds of seeds
/// in moments.
/// </summary>
public sealed class Dungeon
{
    public const byte Wall = 0;
    public const byte Floor = 1;
    /// <summary>Room placements tried before the generator settles for fewer rooms than it rolled.</summary>
    public const int PlaceTries = 400;
    /// <summary>The four steps a creature can take, in the order every search and choice tries them.</summary>
    public static readonly Vector2I[] Dirs = { Vector2I.Up, Vector2I.Right, Vector2I.Down, Vector2I.Left };
    /// <summary>The letter of each kind in ToText() and FromText().</summary>
    private static readonly (string Kind, char Letter)[] KindLetters = { ("shade", 's'), ("bat", 'b'), ("brute", 'B') };

    public int Width { get; private set; }
    public int Height { get; private set; }
    /// <summary>Wall or Floor per cell, row by row (index y * Width + x).</summary>
    public byte[] Tiles { get; private set; } = Array.Empty<byte>();
    /// <summary>Room 0 is where the wick starts.</summary>
    public List<Rect2I> Rooms { get; } = new();
    public Vector2I Start { get; private set; }
    public Vector2I Stairs { get; private set; }
    /// <summary>Each enemy to place, in the order they were rolled.</summary>
    public List<Spawn> Spawns { get; } = new();

    public static Dungeon Generate(long seed, FloorSpec spec)
    {
        var dungeon = new Dungeon { Width = spec.Width, Height = spec.Height };
        using var rng = new RandomNumberGenerator();
        rng.Seed = unchecked((ulong)seed);
        dungeon.Tiles = new byte[dungeon.Width * dungeon.Height];
        dungeon.PlaceRooms(rng, spec);
        dungeon.JoinRooms(rng);
        dungeon.Start = dungeon.Center(0);
        dungeon.Stairs = dungeon.FarthestRoomCenter();
        dungeon.PlaceSpawns(rng, spec);
        return dungeon;
    }

    private void PlaceRooms(RandomNumberGenerator rng, FloorSpec spec)
    {
        int wanted = rng.RandiRange(spec.Rooms[0], spec.Rooms[1]);
        int low = spec.RoomSize[0];
        int high = spec.RoomSize[1];
        for (int i = 0; i < PlaceTries; i++)
        {
            if (Rooms.Count >= wanted)
                break;
            var size = new Vector2I(rng.RandiRange(low, high), rng.RandiRange(low, high));
            var rect = new Rect2I(new Vector2I(rng.RandiRange(1, Width - size.X - 1), rng.RandiRange(1, Height - size.Y - 1)), size);
            // At least one wall between two rooms, so a room's shape stays readable.
            bool free = true;
            foreach (Rect2I room in Rooms)
            {
                if (room.Grow(1).Intersects(rect))
                {
                    free = false;
                    break;
                }
            }
            if (!free)
                continue;
            Rooms.Add(rect);
            for (int y = rect.Position.Y; y < rect.End.Y; y++)
            {
                for (int x = rect.Position.X; x < rect.End.X; x++)
                    Tiles[y * Width + x] = Floor;
            }
        }
    }

    /// <summary>
    /// Each room after the first is dug to the nearest room already joined: a spanning tree grown from room 0, so every
    /// room can be reached from the start whatever the seed.
    /// </summary>
    private void JoinRooms(RandomNumberGenerator rng)
    {
        for (int i = 1; i < Rooms.Count; i++)
        {
            int nearest = 0;
            int best = 1 << 30;
            for (int j = 0; j < i; j++)
            {
                int gap = Manhattan(Center(i), Center(j));
                if (gap < best)
                {
                    best = gap;
                    nearest = j;
                }
            }
            DigCorridor(Center(i), Center(nearest), rng.Randi() % 2 == 0);
        }
    }

    /// <summary>An L-shaped corridor: across then down, or down then across.</summary>
    private void DigCorridor(Vector2I from, Vector2I to, bool acrossFirst)
    {
        Vector2I corner = acrossFirst ? new Vector2I(to.X, from.Y) : new Vector2I(from.X, to.Y);
        DigLine(from, corner);
        DigLine(corner, to);
    }

    private void DigLine(Vector2I from, Vector2I to)
    {
        Vector2I step = (to - from).Sign();
        Vector2I cell = from;
        Tiles[Index(cell)] = Floor;
        while (cell != to)
        {
            cell += step;
            Tiles[Index(cell)] = Floor;
        }
    }

    /// <summary>The stairs go in the room whose centre is the longest walk from the start, so a floor is crossed, not skipped.</summary>
    private Vector2I FarthestRoomCenter()
    {
        int[] field = DistanceField(Start);
        Vector2I best = Center(0);
        int bestDistance = -1;
        for (int i = 1; i < Rooms.Count; i++)
        {
            int distance = field[Index(Center(i))];
            if (distance > bestDistance)
            {
                bestDistance = distance;
                best = Center(i);
            }
        }
        return best;
    }

    /// <summary>Every room but the start holds PerRoom enemies, each of a kind drawn from the floor's list (repeats weigh more).</summary>
    private void PlaceSpawns(RandomNumberGenerator rng, FloorSpec spec)
    {
        List<string> kinds = spec.Enemies;
        var taken = new HashSet<Vector2I> { Start, Stairs };
        for (int i = 1; i < Rooms.Count; i++)
        {
            Rect2I room = Rooms[i];
            int count = rng.RandiRange(spec.PerRoom[0], spec.PerRoom[1]);
            for (int n = 0; n < count; n++)
            {
                var cell = new Vector2I(rng.RandiRange(room.Position.X, room.End.X - 1), rng.RandiRange(room.Position.Y, room.End.Y - 1));
                string kind = kinds[rng.RandiRange(0, kinds.Count - 1)];
                if (!taken.Add(cell))
                    continue;
                Spawns.Add(new Spawn(kind, cell));
            }
        }
    }

    public Vector2I Center(int room) => Rooms[room].Position + Rooms[room].Size / 2;

    public int Index(Vector2I cell) => cell.Y * Width + cell.X;

    public bool InBounds(Vector2I cell) => cell.X >= 0 && cell.Y >= 0 && cell.X < Width && cell.Y < Height;

    public bool IsFloor(Vector2I cell) => InBounds(cell) && Tiles[Index(cell)] == Floor;

    /// <summary>Steps from a cell to every cell over floor (a breadth-first search, four ways); -1 where it cannot be reached.</summary>
    public int[] DistanceField(Vector2I from)
    {
        var field = new int[Width * Height];
        Array.Fill(field, -1);
        if (!IsFloor(from))
            return field;
        var queue = new List<Vector2I> { from };
        field[Index(from)] = 0;
        int head = 0;
        while (head < queue.Count)
        {
            Vector2I cell = queue[head];
            head += 1;
            int nextDistance = field[Index(cell)] + 1;
            foreach (Vector2I dir in Dirs)
            {
                Vector2I next = cell + dir;
                if (IsFloor(next) && field[Index(next)] < 0)
                {
                    field[Index(next)] = nextDistance;
                    queue.Add(next);
                }
            }
        }
        return field;
    }

    /// <summary>Whether nothing but floor lies on the straight line between two cells (Bresenham, the ends not counted).</summary>
    public bool LineClear(Vector2I from, Vector2I to)
    {
        int dx = Math.Abs(to.X - from.X);
        int dy = -Math.Abs(to.Y - from.Y);
        int sx = from.X < to.X ? 1 : -1;
        int sy = from.Y < to.Y ? 1 : -1;
        int error = dx + dy;
        Vector2I cell = from;
        while (cell != to)
        {
            int twice = 2 * error;
            if (twice >= dy)
            {
                error += dy;
                cell.X += sx;
            }
            if (twice <= dx)
            {
                error += dx;
                cell.Y += sy;
            }
            if (cell != to && !IsFloor(cell))
                return false;
        }
        return true;
    }

    /// <summary>Floor cells the start cannot reach: 0 on a valid floor.</summary>
    public int UnreachableCells()
    {
        int[] field = DistanceField(Start);
        int count = 0;
        for (int i = 0; i < Tiles.Length; i++)
        {
            if (Tiles[i] == Floor && field[i] < 0)
                count += 1;
        }
        return count;
    }

    public int FloorCells()
    {
        int count = 0;
        foreach (byte tile in Tiles)
        {
            if (tile == Floor)
                count += 1;
        }
        return count;
    }

    /// <summary>
    /// The floor as text, one row per line: # wall, . floor, S start, &gt; stairs, a letter per spawn (s shade, b bat,
    /// B brute). Two dungeons are the same when their text is, in either language.
    /// </summary>
    public string ToText()
    {
        var rows = new char[Height][];
        for (int y = 0; y < Height; y++)
        {
            rows[y] = new char[Width];
            for (int x = 0; x < Width; x++)
                rows[y][x] = Tiles[y * Width + x] == Floor ? '.' : '#';
        }
        foreach (Spawn spawn in Spawns)
            rows[spawn.Cell.Y][spawn.Cell.X] = LetterOf(spawn.Kind);
        rows[Start.Y][Start.X] = 'S';
        rows[Stairs.Y][Stairs.X] = '>';
        var text = new StringBuilder(Height * (Width + 1));
        for (int y = 0; y < Height; y++)
        {
            if (y > 0)
                text.Append('\n');
            text.Append(rows[y]);
        }
        return text.ToString();
    }

    /// <summary>A floor drawn by hand in ToText()'s letters, for tests: every cell that is not # is floor, and the whole floor is one room.</summary>
    public static Dungeon FromText(params string[] rows)
    {
        var dungeon = new Dungeon { Height = rows.Length, Width = rows[0].Length };
        dungeon.Tiles = new byte[dungeon.Width * dungeon.Height];
        dungeon.Rooms.Add(new Rect2I(0, 0, dungeon.Width, dungeon.Height));
        for (int y = 0; y < dungeon.Height; y++)
        {
            for (int x = 0; x < dungeon.Width; x++)
            {
                char letter = rows[y][x];
                var cell = new Vector2I(x, y);
                if (letter == '#')
                    continue;
                dungeon.Tiles[dungeon.Index(cell)] = Floor;
                if (letter == 'S')
                    dungeon.Start = cell;
                else if (letter == '>')
                    dungeon.Stairs = cell;
                else if (KindOf(letter) is string kind)
                    dungeon.Spawns.Add(new Spawn(kind, cell));
            }
        }
        return dungeon;
    }

    private static char LetterOf(string kind)
    {
        foreach ((string Kind, char Letter) pair in KindLetters)
        {
            if (pair.Kind == kind)
                return pair.Letter;
        }
        return string.IsNullOrEmpty(kind) ? '?' : kind[0];
    }

    private static string? KindOf(char letter)
    {
        foreach ((string Kind, char Letter) pair in KindLetters)
        {
            if (pair.Letter == letter)
                return pair.Kind;
        }
        return null;
    }

    private static int Manhattan(Vector2I a, Vector2I b) => Math.Abs(a.X - b.X) + Math.Abs(a.Y - b.Y);
}
