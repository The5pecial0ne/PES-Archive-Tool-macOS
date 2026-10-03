using System.IO;
using System.IO.Compression;

namespace GzsTool.Core.Utility
{
    internal static class Compression
    {
        // The original used Ionic's ZlibStream (Zlib.Portable). Modern .NET ships a
        // zlib stream of its own, so the extra package is no longer needed.
        internal static Stream UncompressStream(Stream stream)
        {
            return new ZLibStream(stream, CompressionMode.Decompress, false);
        }

        internal static Stream CompressStream(Stream stream)
        {
            // SmallestSize is the counterpart of Ionic's BestCompression (zlib level 9).
            return new ZLibStream(stream, CompressionLevel.SmallestSize, true);
        }
    }
}
