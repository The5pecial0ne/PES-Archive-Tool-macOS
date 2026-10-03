using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using GzsTool.Core.Common.Interfaces;

namespace GzsTool.Core.Common
{
    public class FileSystemDirectory : IDirectory
    {
        private readonly string _baseDirectoryPath;
        private readonly string _name;

        public FileSystemDirectory(string baseDirectoryPath)
        {
            _baseDirectoryPath = baseDirectoryPath;
            _name = Path.GetFileName(baseDirectoryPath);
        }

        public byte[] ReadFile(string filePath)
        {
            using (var stream = ReadFileStream(filePath))
            {
                return stream.ToArray();
            }
        }

        // Archive entries (and the generated xml files) spell their paths the Windows way,
        // e.g. "Assets\pes16\model\foo.fmdl". On macOS and Linux a backslash is just an
        // ordinary file name character, so translate to the local separator before we
        // touch the disk. The xml stays untouched and remains interchangeable with Windows.
        private static string ToNativePath(string filePath)
        {
            return filePath
                .Replace('\\', Path.DirectorySeparatorChar)
                .Replace('/', Path.DirectorySeparatorChar)
                // A leading separator would make Path.Combine ignore the base directory.
                .TrimStart(Path.DirectorySeparatorChar);
        }

        public Stream ReadFileStream(string filePath)
        {
            string inputFilePath = Path.Combine(_baseDirectoryPath, ToNativePath(filePath));
            FileStream stream = new FileStream(inputFilePath, FileMode.Open, FileAccess.Read, FileShare.Read);
            return stream;
        }

        public void WriteFile(string filePath, Func<Stream> fileContentStream)
        {
            string outputFilePath = Path.Combine(_baseDirectoryPath, ToNativePath(filePath));
            Directory.CreateDirectory(Path.GetDirectoryName(outputFilePath));
            using (Stream input = fileContentStream())
            using (FileStream output = new FileStream(outputFilePath, FileMode.Create))
            {
                input.CopyTo(output);
            }
        }
        
        public IEnumerable<IFileSystemEntry> Entries
        {
            get { return GetEntries(); }
        }

        public string Name
        {
            get { return _name; }
        }

        private IEnumerable<IFileSystemEntry> GetEntries()
        {
            List<IFileSystemEntry> entries = new List<IFileSystemEntry>();
            DirectoryInfo baseDirectoryInfo = new DirectoryInfo(_baseDirectoryPath);
            entries.AddRange(baseDirectoryInfo.GetDirectories().Select(d => new FileSystemDirectory(d.FullName)));
            entries.AddRange(baseDirectoryInfo.GetFiles().Select(f => new FileSystemFile(f.FullName)));
            return entries.OrderBy(e => e.Name);
        }
    }
}
