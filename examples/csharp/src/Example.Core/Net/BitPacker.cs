namespace Example.Core.Net;

// Bit packing, after "The TRIBES Engine Networking Model" (Frohnmayer and Gift, Dynamix): "virtually all data is
// transmitted using the smallest number of bits possible": a bool in 1 bit, an int in as many bits as its range needs,
// a float as a step number in a known range. Godot has no bit stream (StreamPeerBuffer works in whole bytes), so a game
// packs into a byte[] here and sends that as one packet. Both ends must read exactly what was written, field by field:
// reading past the end throws, and Finish() throws when a whole byte or more was left unread, so a reader and writer
// that disagree fail in a test instead of misreading silently.

/// <summary>Sizes shared by <see cref="BitWriter"/> and <see cref="BitReader"/>.</summary>
public static class BitPacking
{
    /// <summary>Bits needed for every value from 0 to <paramref name="maxValue"/> (at least 1).</summary>
    public static int BitsFor(uint maxValue) => maxValue == 0 ? 1 : 32 - System.Numerics.BitOperations.LeadingZeroCount(maxValue);

    /// <summary>
    /// Steps in [<paramref name="min"/>, <paramref name="max"/>] so that each is at most <paramref name="precision"/>
    /// wide; a value is sent as its nearest step, so it comes back at most half a precision off.
    /// </summary>
    public static uint Steps(float min, float max, float precision)
    {
        if (!(max > min) || !(precision > 0)) throw new ArgumentOutOfRangeException(nameof(precision), "need min < max and precision > 0");
        double steps = Math.Ceiling((max - (double)min) / precision);
        return steps <= uint.MaxValue - 1 ? (uint)steps : throw new ArgumentOutOfRangeException(nameof(precision), "more than 32 bits of steps");
    }

    public static int QuantizedBits(float min, float max, float precision) => BitsFor(Steps(min, max, precision));
}

/// <summary>
/// Writes values in as few bits as their range needs; <see cref="ToArray"/> gives the bytes to send. Bits gather in a
/// 64-bit accumulator and go out a whole byte at a time into a buffer that <see cref="Reset"/> keeps, so a server that
/// writes a snapshot for every client every tick allocates nothing but the array it sends (the first writer, one bit at a
/// time into a List of bytes, cost a 100-player server about 13 ms a tick; issue 305). The layout is unchanged: least
/// significant bit first, fields back to back (pinned by BitPackerTests' golden bytes).
/// </summary>
public sealed class BitWriter
{
    byte[] _buffer = new byte[64];
    int _length;          // whole bytes in _buffer
    ulong _pending;       // bits not yet a whole byte, lowest first
    int _pendingBits;     // 0 to 7 between writes

    public int BitCount { get; private set; }
    public int ByteCount => (BitCount + 7) / 8;

    public void WriteBool(bool value) => WriteUInt(value ? 1u : 0u, 1);

    /// <summary>Writes <paramref name="value"/> in <paramref name="bits"/> bits (1 to 32); throws when it does not fit.</summary>
    public void WriteUInt(uint value, int bits)
    {
        if (bits is < 1 or > 32) throw new ArgumentOutOfRangeException(nameof(bits), "1 to 32 bits");
        if (bits < 32 && value >> bits != 0) throw new ArgumentOutOfRangeException(nameof(value), $"{value} does not fit in {bits} bits");
        _pending |= (ulong)value << _pendingBits;   // at most 7 + 32 bits: fits
        _pendingBits += bits;
        BitCount += bits;
        if (_pendingBits < 8) return;
        if (_length + 5 > _buffer.Length) Array.Resize(ref _buffer, _buffer.Length * 2);
        while (_pendingBits >= 8)
        {
            _buffer[_length++] = (byte)_pending;
            _pending >>= 8;
            _pendingBits -= 8;
        }
    }

    /// <summary>Empties the writer for the next packet, keeping its buffer.</summary>
    public void Reset()
    {
        _length = 0;
        _pending = 0;
        _pendingBits = 0;
        BitCount = 0;
    }

    /// <summary>An int in [<paramref name="min"/>, <paramref name="max"/>], as its offset from min.</summary>
    public void WriteInt(int value, int min, int max)
    {
        if (min > max || value < min || value > max) throw new ArgumentOutOfRangeException(nameof(value), $"{value} is outside {min}..{max}");
        WriteUInt((uint)((long)value - min), BitPacking.BitsFor((uint)((long)max - min)));
    }

    /// <summary>
    /// A float in [<paramref name="min"/>, <paramref name="max"/>] as its nearest step of at most
    /// <paramref name="precision"/> (Overwatch sends positions at 1/1024 m). Out of range or NaN throws: widen the range
    /// rather than clamp a value the game believes.
    /// </summary>
    public void WriteQuantized(float value, float min, float max, float precision)
    {
        uint steps = BitPacking.Steps(min, max, precision);
        if (!(value >= min && value <= max)) throw new ArgumentOutOfRangeException(nameof(value), $"{value} is outside {min}..{max}");
        uint step = (uint)Math.Round((value - (double)min) / (max - (double)min) * steps);
        WriteUInt(step, BitPacking.BitsFor(steps));
    }

    /// <summary>The bytes written so far (the last one padded with zero bits); the writer can go on writing.</summary>
    public byte[] ToArray()
    {
        var bytes = new byte[ByteCount];
        Array.Copy(_buffer, bytes, _length);
        if (_pendingBits > 0) bytes[_length] = (byte)_pending;
        return bytes;
    }
}

/// <summary>Reads what a <see cref="BitWriter"/> wrote, in the same order and with the same sizes.</summary>
public sealed class BitReader
{
    readonly byte[] _bytes;
    int _position;

    public BitReader(byte[] bytes) => _bytes = bytes;

    public int BitsLeft => _bytes.Length * 8 - _position;

    public bool ReadBool() => ReadUInt(1) != 0;

    public uint ReadUInt(int bits)
    {
        if (bits is < 1 or > 32) throw new ArgumentOutOfRangeException(nameof(bits), "1 to 32 bits");
        if (bits > BitsLeft) throw new InvalidOperationException($"read of {bits} bits with {BitsLeft} left: the reader and writer disagree");
        // The (at most 5) bytes the field touches, least significant first, then shifted and masked: no loop per bit.
        int first = _position >> 3, offset = _position & 7, last = (_position + bits - 1) >> 3;
        ulong chunk = 0;
        for (int i = first; i <= last; i++) chunk |= (ulong)_bytes[i] << (8 * (i - first));
        _position += bits;
        return (uint)((chunk >> offset) & (bits == 32 ? 0xFFFF_FFFFUL : (1UL << bits) - 1));
    }

    public int ReadInt(int min, int max) => (int)(min + (long)ReadUInt(BitPacking.BitsFor((uint)((long)max - min))));

    public float ReadQuantized(float min, float max, float precision)
    {
        uint steps = BitPacking.Steps(min, max, precision);
        uint step = ReadUInt(BitPacking.BitsFor(steps));
        if (step > steps) throw new InvalidOperationException($"step {step} is past {steps}: the reader and writer disagree");
        return (float)(min + (max - (double)min) * step / steps);
    }

    /// <summary>Throws when a whole byte or more is left: the writer wrote a field this reader skipped.</summary>
    public void Finish()
    {
        if (BitsLeft >= 8) throw new InvalidOperationException($"{BitsLeft} bits left unread: the reader and writer disagree");
    }
}
