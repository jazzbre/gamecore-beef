using System;
using System.IO;
using System.Collections;

namespace GameCore;

public class PngImageWriter
{
    private uint32[256] crcTable;
    private List<uint8> scanlines = new .() ~ delete _;

    public this()
    {
        for (uint32 tableIndex = 0; tableIndex < 256; tableIndex++)
        {
            uint32 remainder = tableIndex;
            for (int bitIndex = 0; bitIndex < 8; bitIndex++)
            {
                remainder = (remainder >> 1) ^ ((remainder & 1) != 0 ? 0xEDB88320U : 0U);
            }
            crcTable[tableIndex] = remainder;
        }
    }

    private void UpdateCrc(ref uint32 crc, Span<uint8> bytes)
    {
        for (let value in bytes)
        {
            crc = crcTable[(crc ^ value) & 255] ^ (crc >> 8);
        }
    }

    private static void StoreBigEndian(Span<uint8> bytes, int offset, uint32 value)
    {
        bytes[offset] = (uint8)(value >> 24);
        bytes[offset + 1] = (uint8)(value >> 16);
        bytes[offset + 2] = (uint8)(value >> 8);
        bytes[offset + 3] = (uint8)value;
    }

    private static bool WriteBytes(Stream stream, Span<uint8> bytes)
    {
        return (stream.TryWrite(bytes) case .Ok(let written)) && written == bytes.Length;
    }

    private static bool WriteBigEndian(Stream stream, uint32 value)
    {
        uint8[4] bytes = default;
        StoreBigEndian(bytes, 0, value);
        return WriteBytes(stream, bytes);
    }

    private bool WriteChunk(Stream stream, StringView type, Span<uint8> data)
    {
        let typeBytes = Span<uint8>((uint8*)type.Ptr, 4);
        uint32 crc = 0xFFFFFFFF;
        UpdateCrc(ref crc, typeBytes);
        UpdateCrc(ref crc, data);
        return WriteBigEndian(stream, (uint32)data.Length) && WriteBytes(stream, typeBytes) &&
            WriteBytes(stream, data) && WriteBigEndian(stream, crc ^ 0xFFFFFFFF);
    }

    public bool WriteBgra8(StringView path, int width, int height, Span<uint8> pixels)
    {
        uint64 sourceSize = (uint64)Math.Max(width, 0) * (uint64)Math.Max(height, 0) * 4;
        uint64 scanlineSize = ((uint64)Math.Max(width, 0) * 3 + 1) * (uint64)Math.Max(height, 0);
        if (width <= 0 || height <= 0 || sourceSize > (uint64)pixels.Length || scanlineSize > int32.MaxValue)
        {
            return false;
        }
        scanlines.Resize((int)scanlineSize);
        int destinationIndex = 0;
        int sourceIndex = 0;
        for (int rowIndex = 0; rowIndex < height; rowIndex++)
        {
            scanlines[destinationIndex++] = 0;
            for (int columnIndex = 0; columnIndex < width; columnIndex++)
            {
                scanlines[destinationIndex++] = pixels[sourceIndex + 2];
                scanlines[destinationIndex++] = pixels[sourceIndex + 1];
                scanlines[destinationIndex++] = pixels[sourceIndex];
                sourceIndex += 4;
            }
        }

        let file = scope FileStream();
        if (file.Create(path, .Write) case .Err)
        {
            return false;
        }
        uint8[8] signature = .(137, 80, 78, 71, 13, 10, 26, 10);
        uint8[13] header = default;
        StoreBigEndian(header, 0, (uint32)width);
        StoreBigEndian(header, 4, (uint32)height);
        header[8] = 8;
        header[9] = 2;
        uint8[1] renderingIntent = .(0);
        if (!WriteBytes(file, signature) || !WriteChunk(file, "IHDR", header) || !WriteChunk(file, "sRGB", renderingIntent))
        {
            return false;
        }

        // Stored DEFLATE blocks keep capture independent of native compression libraries.
        uint32 blockCount = ((uint32)scanlines.Count + 65534) / 65535;
        uint32 dataLength = (uint32)scanlines.Count + blockCount * 5 + 6;
        uint8[4] dataType = .(73, 68, 65, 84);
        uint8[2] zlibHeader = .(0x78, 0x01);
        uint32 crc = 0xFFFFFFFF;
        UpdateCrc(ref crc, dataType);
        UpdateCrc(ref crc, zlibHeader);
        if (!WriteBigEndian(file, dataLength) || !WriteBytes(file, dataType) || !WriteBytes(file, zlibHeader))
        {
            return false;
        }
        uint64 adlerFirst = 1;
        uint64 adlerSecond = 0;
        int offset = 0;
        while (offset < scanlines.Count)
        {
            uint16 blockLength = (uint16)Math.Min(65535, scanlines.Count - offset);
            uint16 inverseLength = ~blockLength;
            bool lastBlock = offset + blockLength == scanlines.Count;
            uint8[5] blockHeader = .((uint8)(lastBlock ? 1 : 0),
                (uint8)blockLength, (uint8)(blockLength >> 8), (uint8)inverseLength, (uint8)(inverseLength >> 8));
            let block = Span<uint8>(scanlines.Ptr + offset, blockLength);
            UpdateCrc(ref crc, blockHeader);
            UpdateCrc(ref crc, block);
            for (let value in block)
            {
                adlerFirst += value;
                adlerSecond += adlerFirst;
            }
            adlerFirst %= 65521;
            adlerSecond %= 65521;
            if (!WriteBytes(file, blockHeader) || !WriteBytes(file, block))
            {
                return false;
            }
            offset += blockLength;
        }
        uint8[4] adler = default;
        StoreBigEndian(adler, 0, (uint32)((adlerSecond << 16) | adlerFirst));
        UpdateCrc(ref crc, adler);
        return WriteBytes(file, adler) && WriteBigEndian(file, crc ^ 0xFFFFFFFF) && WriteChunk(file, "IEND", default);
    }
}
