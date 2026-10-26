namespace Glimmerpit;

using System;
using System.Buffers.Binary;
using System.Collections;
using System.Collections.Generic;
using System.Text;

/// <summary>
/// The netcode's messages and their bytes. A message is a <c>Dictionary&lt;string, object?&gt;</c> of numbers, booleans,
/// strings, lists and dictionaries, never objects, and its bytes are the engine's <c>var_to_bytes</c> format, written and
/// read here in managed code: the GDScript version's server and clients read them, and a match sends and receives some
/// hundred messages a second without making an engine Variant, Array or Dictionary for each (each holds native memory
/// until the garbage collector finalizes it, which a long-running server sees as resident memory that keeps growing).
/// </summary>
/// <remarks>
/// Decoded integers come back as <c>long</c>, floats as <c>double</c>, arrays as <c>List&lt;object?&gt;</c> and dictionaries
/// with string keys as <c>Dictionary&lt;string, object?&gt;</c>; anything else, or bytes that are not a whole message, gives
/// null. A dictionary is written in the order its keys were added, which is the order of a dictionary nothing was removed from.
/// </remarks>
public static class Wire
{
    private const int TypeNil = 0;
    private const int TypeBool = 1;
    private const int TypeInt = 2;
    private const int TypeFloat = 3;
    private const int TypeString = 4;
    private const int TypeDictionary = 27;
    private const int TypeArray = 28;
    /// <summary>The header flag of an integer or float written in 64 bits.</summary>
    private const int Flag64 = 1 << 16;
    /// <summary>Nesting deeper than any message goes: deeper input is refused rather than followed.</summary>
    private const int MaxDepth = 16;

    public static byte[] Encode(object? value)
    {
        var buffer = new List<byte>(256);
        Write(buffer, value, 0);
        return buffer.ToArray();
    }

    /// <summary>The message in the bytes, or null when they hold none (a server never trusts the wire).</summary>
    public static object? Decode(byte[] bytes)
    {
        int at = 0;
        try
        {
            object? value = Read(bytes, ref at, 0);
            return at == bytes.Length ? value : null;
        }
        catch (FormatException)
        {
            return null;
        }
    }

    /// <summary>A whole number from a decoded or built message: an int, a long, a whole float or a boolean; else the fallback.</summary>
    public static int Int(object? value, int fallback = 0) => value switch
    {
        int i => i,
        long l => (int)Math.Clamp(l, int.MinValue, int.MaxValue),
        double d when !double.IsNaN(d) => (int)Math.Clamp(d, int.MinValue, int.MaxValue),
        bool b => b ? 1 : 0,
        _ => fallback,
    };

    public static bool Flag(object? value) => value switch
    {
        bool b => b,
        int i => i != 0,
        long l => l != 0,
        double d => d != 0.0,
        _ => false,
    };

    public static string Text(object? value, string fallback = "") => value as string ?? fallback;

    public static Dictionary<string, object?>? Map(object? value) => value as Dictionary<string, object?>;

    public static IList? List(object? value) => value is string ? null : value as IList;

    /// <summary>A message's field, or null when the message lacks it.</summary>
    public static object? Get(Dictionary<string, object?> message, string key) => message.TryGetValue(key, out object? value) ? value : null;

    /// <summary>A list of whole numbers (scores, owners), as Int reads each.</summary>
    public static List<int> Ints(object? value)
    {
        var ints = new List<int>();
        if (List(value) is IList list)
        {
            foreach (object? item in list)
                ints.Add(Int(item));
        }
        return ints;
    }

    private static void Write(List<byte> buffer, object? value, int depth)
    {
        if (depth > MaxDepth)
            throw new ArgumentException("Wire: a message nests too deep");
        switch (value)
        {
            case null:
                WriteInt32(buffer, TypeNil);
                break;
            case bool b:
                WriteInt32(buffer, TypeBool);
                WriteInt32(buffer, b ? 1 : 0);
                break;
            case int i:
                WriteInt32(buffer, TypeInt);
                WriteInt32(buffer, i);
                break;
            case long l when l >= int.MinValue && l <= int.MaxValue:
                WriteInt32(buffer, TypeInt);
                WriteInt32(buffer, (int)l);
                break;
            case long l:
                WriteInt32(buffer, TypeInt | Flag64);
                WriteInt64(buffer, l);
                break;
            case float f:
                WriteInt32(buffer, TypeFloat);
                WriteInt32(buffer, BitConverter.SingleToInt32Bits(f));
                break;
            case double d when (double)(float)d == d:
                WriteInt32(buffer, TypeFloat);
                WriteInt32(buffer, BitConverter.SingleToInt32Bits((float)d));
                break;
            case double d:
                WriteInt32(buffer, TypeFloat | Flag64);
                WriteInt64(buffer, BitConverter.DoubleToInt64Bits(d));
                break;
            case string s:
                WriteInt32(buffer, TypeString);
                WriteString(buffer, s);
                break;
            case IDictionary<string, object?> map:
                WriteInt32(buffer, TypeDictionary);
                WriteInt32(buffer, map.Count);
                foreach (KeyValuePair<string, object?> pair in map)
                {
                    WriteInt32(buffer, TypeString);
                    WriteString(buffer, pair.Key);
                    Write(buffer, pair.Value, depth + 1);
                }
                break;
            case IList list:
                WriteInt32(buffer, TypeArray);
                WriteInt32(buffer, list.Count);
                foreach (object? item in list)
                    Write(buffer, item, depth + 1);
                break;
            default:
                throw new ArgumentException($"Wire: a message cannot hold a {value.GetType().Name}");
        }
    }

    private static void WriteInt32(List<byte> buffer, int value)
    {
        Span<byte> bytes = stackalloc byte[4];
        BinaryPrimitives.WriteInt32LittleEndian(bytes, value);
        foreach (byte b in bytes)
            buffer.Add(b);
    }

    private static void WriteInt64(List<byte> buffer, long value)
    {
        Span<byte> bytes = stackalloc byte[8];
        BinaryPrimitives.WriteInt64LittleEndian(bytes, value);
        foreach (byte b in bytes)
            buffer.Add(b);
    }

    private static void WriteString(List<byte> buffer, string s)
    {
        byte[] utf8 = Encoding.UTF8.GetBytes(s);
        WriteInt32(buffer, utf8.Length);
        buffer.AddRange(utf8);
        // Padded to whole 32-bit words, as the engine writes them.
        while (buffer.Count % 4 != 0)
            buffer.Add(0);
    }

    private static object? Read(byte[] bytes, ref int at, int depth)
    {
        if (depth > MaxDepth)
            throw new FormatException();
        int header = ReadInt32(bytes, ref at);
        int type = header & 0xFF;
        bool wide = (header & Flag64) != 0;
        switch (type)
        {
            case TypeNil:
                return null;
            case TypeBool:
                return ReadInt32(bytes, ref at) != 0;
            case TypeInt:
                return wide ? ReadInt64(bytes, ref at) : ReadInt32(bytes, ref at);
            case TypeFloat:
                return wide ? BitConverter.Int64BitsToDouble(ReadInt64(bytes, ref at)) : (double)BitConverter.Int32BitsToSingle(ReadInt32(bytes, ref at));
            case TypeString:
                return ReadString(bytes, ref at);
            case TypeDictionary:
            {
                if ((header >> 16) != 0)
                    throw new FormatException();   // a typed dictionary: no message is one
                int count = ReadInt32(bytes, ref at) & 0x7FFFFFFF;
                var map = new Dictionary<string, object?>();
                for (int i = 0; i < count; i++)
                {
                    if (Read(bytes, ref at, depth + 1) is not string key)
                        throw new FormatException();
                    map[key] = Read(bytes, ref at, depth + 1);
                }
                return map;
            }
            case TypeArray:
            {
                if ((header >> 16) != 0)
                    throw new FormatException();   // a typed array: no message is one
                int count = ReadInt32(bytes, ref at) & 0x7FFFFFFF;
                // Every element takes at least four bytes, so a count beyond what is left is a lie.
                if (count > (bytes.Length - at) / 4)
                    throw new FormatException();
                var list = new List<object?>(count);
                for (int i = 0; i < count; i++)
                    list.Add(Read(bytes, ref at, depth + 1));
                return list;
            }
            default:
                throw new FormatException();
        }
    }

    private static int ReadInt32(byte[] bytes, ref int at)
    {
        if (at < 0 || bytes.Length - at < 4)
            throw new FormatException();
        int value = BinaryPrimitives.ReadInt32LittleEndian(bytes.AsSpan(at, 4));
        at += 4;
        return value;
    }

    private static long ReadInt64(byte[] bytes, ref int at)
    {
        if (at < 0 || bytes.Length - at < 8)
            throw new FormatException();
        long value = BinaryPrimitives.ReadInt64LittleEndian(bytes.AsSpan(at, 8));
        at += 8;
        return value;
    }

    private static string ReadString(byte[] bytes, ref int at)
    {
        int length = ReadInt32(bytes, ref at);
        if (length < 0 || length > bytes.Length - at)
            throw new FormatException();
        string text = Encoding.UTF8.GetString(bytes, at, length);
        at += length;
        if (length % 4 != 0)
            at += 4 - length % 4;
        if (at > bytes.Length)
            throw new FormatException();
        return text;
    }
}
