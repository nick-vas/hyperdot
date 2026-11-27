using Example.Core.Net;
using Xunit;
using Xunit.Abstractions;

namespace Example.Core.Tests;

/// <summary>TRIBES-style bit packing: every type round-trips, floats come back within half a step, and a mismatch fails.</summary>
public sealed class BitPackerTests
{
    readonly ITestOutputHelper _output;
    public BitPackerTests(ITestOutputHelper output) => _output = output;

    // The wire layout, pinned: a field sequence and the exact bytes the writer must produce (least significant bit first,
    // fields packed back to back, a 32-bit field crossing byte boundaries). Recorded from the bit-by-bit writer before it
    // was rewritten around a 64-bit accumulator (issue 305), so the two agree byte for byte.
    static void WriteGoldenSequence(BitWriter w)
    {
        w.WriteBool(true);
        w.WriteUInt(5, 3);
        w.WriteUInt(0xDEADBEEF, 32);
        w.WriteInt(-7, -300, 300);
        w.WriteQuantized(1.5f, -10f, 10f, 0.01f);
        w.WriteUInt(1, 1);
        w.WriteUInt(0x3FF, 10);
        w.WriteUInt(0, 32);
        w.WriteUInt(uint.MaxValue, 32);
        w.WriteBool(false);
    }

    const string GoldenHex = "FBEEDBEA5DD21FFF0F000000F0FFFFFF0F";

    [Fact]
    public void TheWireLayoutIsUnchanged()
    {
        var writer = new BitWriter();
        WriteGoldenSequence(writer);
        string hex = Convert.ToHexString(writer.ToArray());
        _output.WriteLine($"golden: {writer.BitCount} bits, {hex}");
        Assert.Equal(GoldenHex, hex);

        var reader = new BitReader(writer.ToArray());
        Assert.True(reader.ReadBool());
        Assert.Equal(5u, reader.ReadUInt(3));
        Assert.Equal(0xDEADBEEFu, reader.ReadUInt(32));
        Assert.Equal(-7, reader.ReadInt(-300, 300));
        Assert.Equal(1.5f, reader.ReadQuantized(-10f, 10f, 0.01f), 0.005f);
        Assert.Equal(1u, reader.ReadUInt(1));
        Assert.Equal(0x3FFu, reader.ReadUInt(10));
        Assert.Equal(0u, reader.ReadUInt(32));
        Assert.Equal(uint.MaxValue, reader.ReadUInt(32));
        Assert.False(reader.ReadBool());
        reader.Finish();
    }

    [Fact]
    public void AResetWriterWritesTheSameBytesAgain()
    {
        var writer = new BitWriter();
        WriteGoldenSequence(writer);
        var mid = writer.ToArray();                           // ToArray leaves the writer writing
        writer.WriteUInt(0x2A, 7);
        Assert.Equal(GoldenHex, Convert.ToHexString(mid));
        writer.Reset();
        Assert.Equal(0, writer.BitCount);
        Assert.Empty(writer.ToArray());
        for (int packet = 0; packet < 3; packet++)            // the same buffer, packet after packet
        {
            writer.Reset();
            WriteGoldenSequence(writer);
            Assert.Equal(GoldenHex, Convert.ToHexString(writer.ToArray()));
        }
        writer.Reset();
        for (int i = 0; i < 1000; i++) writer.WriteUInt((uint)i, 10);   // grows past its first buffer
        var reader = new BitReader(writer.ToArray());
        for (int i = 0; i < 1000; i++) Assert.Equal((uint)i, reader.ReadUInt(10));
        reader.Finish();
    }

    [Fact]
    public void EveryTypeRoundTrips()
    {
        var random = new Random(5);
        var writer = new BitWriter();
        var bools = new List<bool>();
        var uints = new List<(uint Value, int Bits)>();
        var ints = new List<int>();
        for (int i = 0; i < 200; i++)
        {
            bool b = random.Next(2) == 1;
            int bits = random.Next(1, 33);
            uint u = bits == 32 ? (uint)random.NextInt64(0, 1L << 32) : (uint)random.NextInt64(0, 1L << bits);
            int n = random.Next(-300, 301);
            writer.WriteBool(b); writer.WriteUInt(u, bits); writer.WriteInt(n, -300, 300);
            bools.Add(b); uints.Add((u, bits)); ints.Add(n);
        }
        var reader = new BitReader(writer.ToArray());
        for (int i = 0; i < 200; i++)
        {
            Assert.Equal(bools[i], reader.ReadBool());
            Assert.Equal(uints[i].Value, reader.ReadUInt(uints[i].Bits));
            Assert.Equal(ints[i], reader.ReadInt(-300, 300));
        }
        reader.Finish();
        Assert.Equal(writer.ByteCount, writer.ToArray().Length);
    }

    [Theory]
    [InlineData(-1024f, 1024f, 1f / 1024)]   // a position at Overwatch's 1/1024 m
    [InlineData(0f, 1f, 0.01f)]
    [InlineData(-3.14159265f, 3.14159265f, 0.001f)]
    public void QuantizedFloatsComeBackWithinHalfAStep(float min, float max, float precision)
    {
        var random = new Random(9);
        var values = Enumerable.Range(0, 2000).Select(_ => (float)(min + random.NextDouble() * (max - (double)min))).Append(min).Append(max).ToList();
        var writer = new BitWriter();
        foreach (float v in values) writer.WriteQuantized(v, min, max, precision);
        Assert.Equal(values.Count * BitPacking.QuantizedBits(min, max, precision), writer.BitCount);

        var reader = new BitReader(writer.ToArray());
        float worst = 0;
        foreach (float v in values) worst = Math.Max(worst, Math.Abs(reader.ReadQuantized(min, max, precision) - v));
        reader.Finish();
        float ulp = MathF.BitIncrement(Math.Max(Math.Abs(min), Math.Abs(max))) - Math.Max(Math.Abs(min), Math.Abs(max));
        Assert.True(worst <= precision / 2 + ulp, $"worst error {worst} for precision {precision}");
        _output.WriteLine($"{min}..{max} at {precision}: {BitPacking.QuantizedBits(min, max, precision)} bits, worst error {worst}");
    }

    [Fact]
    public void AReaderThatDisagreesWithTheWriterFails()
    {
        var writer = new BitWriter();
        writer.WriteInt(5, 0, 100);   // 7 bits
        writer.WriteBool(true);
        Assert.Throws<InvalidOperationException>(() => new BitReader(writer.ToArray()).ReadInt(0, 1000));   // 10 bits: past the end

        writer.WriteUInt(70000, 20);
        var shortReader = new BitReader(writer.ToArray());
        shortReader.ReadInt(0, 100); shortReader.ReadBool();
        Assert.Throws<InvalidOperationException>(shortReader.Finish);   // a field was left unread

        var steps = new BitWriter();
        steps.WriteUInt(31, 5);   // 31 is not a step of 0..1 at 0.05 (20 steps, 5 bits)
        Assert.Throws<InvalidOperationException>(() => new BitReader(steps.ToArray()).ReadQuantized(0, 1, 0.05f));

        Assert.Throws<ArgumentOutOfRangeException>(() => new BitWriter().WriteUInt(8, 3));
        Assert.Throws<ArgumentOutOfRangeException>(() => new BitWriter().WriteInt(101, 0, 100));
        Assert.Throws<ArgumentOutOfRangeException>(() => new BitWriter().WriteQuantized(1.5f, 0, 1, 0.01f));
        Assert.Throws<ArgumentOutOfRangeException>(() => new BitWriter().WriteQuantized(float.NaN, 0, 1, 0.01f));
    }

    // A ghost's state at 4 bytes a value (GhostFormat.Uniform) against the same state packed: a position in a 2 km
    // world at 1/1024 m, health 0..100, an animation of 16, and alive.
    [Fact]
    public void APackedGhostNeedsAboutAThirdOfTheBytes()
    {
        var writer = new BitWriter();
        writer.WriteQuantized(311.25f, -1024, 1024, 1f / 1024);
        writer.WriteQuantized(-87.5f, -1024, 1024, 1f / 1024);
        writer.WriteInt(73, 0, 100);
        writer.WriteUInt(9, 4);
        writer.WriteBool(true);
        int fixedBytes = 5 * sizeof(int);
        _output.WriteLine($"{writer.BitCount} bits, {writer.ByteCount} bytes packed against {fixedBytes} at 4 bytes a value");
        Assert.Equal(22 + 22 + 7 + 4 + 1, writer.BitCount);
        Assert.Equal(7, writer.ByteCount);
        Assert.True(writer.ByteCount * 2 < fixedBytes);

        var reader = new BitReader(writer.ToArray());
        Assert.Equal(311.25f, reader.ReadQuantized(-1024, 1024, 1f / 1024));
        Assert.Equal(-87.5f, reader.ReadQuantized(-1024, 1024, 1f / 1024));
        Assert.Equal(73, reader.ReadInt(0, 100));
        Assert.Equal(9u, reader.ReadUInt(4));
        Assert.True(reader.ReadBool());
        reader.Finish();
    }
}
