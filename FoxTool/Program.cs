using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using FoxTool.Fox;

namespace FoxTool
{
    public static class Program
    {
        private static readonly Dictionary<ulong, string> GlobalHashNameDictionary = new Dictionary<ulong, string>();

        private static readonly List<string> DecompilableExtensions = new List<string>
        {
            ".bnd",
            ".clo",
            ".des",
            ".evf",
            ".fox2",
            ".fsd",
            ".lad",
            ".parts",
            ".ph",
            ".phsd",
            ".sdf",
            ".sim",
            ".tgt",
            ".vdp",
            ".veh",
            ".vfxlf"
        };

        private static void Main(string[] args)
        {
            if (args.Length == 1)
            {
                string path = args[0];
                if (File.Exists(path))
                {
                    string fileExtension = Path.GetExtension(path);
                    // Also fagx, fdmg, fox
                    if (fileExtension.Equals(".xml", StringComparison.OrdinalIgnoreCase))
                    {
                        CompileFile(path);
                        return;
                    }
                    if (IsDecompilable(fileExtension))
                    {
                        DecompileFile(path);
                        return;
                    }
                    ShowNotDecompilableError();
                    return;
                }
                if (Directory.Exists(path))
                {
                    DecompileFile(path);
                    return;
                }
            }
            else if (args.Length == 2)
            {
                string option = args[0];
                switch (option)
                {
                    case "-c":
                        CompileFile(args[1]);
                        return;
                    case "-d":
                        DecompileFile(args[1]);
                        return;
                    default:
                        Console.WriteLine("Unknown option: {0}", option);
                        return;
                }
            }
            ShowUsageInfo();
        }

        private static void CompileFile(string path)
        {
            var fileNameWithoutExtension = Path.GetFileNameWithoutExtension(path);
            string outFileName = Path.Combine(Path.GetDirectoryName(path), fileNameWithoutExtension);

            // Write under a temporary name and only swap the result in once it is complete,
            // so a broken xml can't leave an empty or half-written file where a good one was.
            string temporaryFileName = outFileName + ".tmp";
            try
            {
                Console.WriteLine("Compiling {0}", path);
                using (FileStream input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
                using (FileStream output = new FileStream(temporaryFileName, FileMode.Create))
                {
                    FoxConverter.CompileFox(input, output);
                }

                File.Move(temporaryFileName, outFileName, true);
            }
            catch (Exception e)
            {
                Console.WriteLine("Error compiling {0}: {1}", path, e);
                ReportFailure(temporaryFileName);
            }
        }

        // Lets whoever started us (a script, the macOS app) see that something went wrong,
        // and clears away the unfinished output.
        private static void ReportFailure(string temporaryFileName)
        {
            Environment.ExitCode = 1;
            if (File.Exists(temporaryFileName))
            {
                File.Delete(temporaryFileName);
            }
        }

        private static void ShowUsageInfo()
        {
            Console.WriteLine("FoxTool by Atvaark\n" +
                              "  A tool for compiling and decompiling Fox Engine XML files.\n" +
                              "Information:\n" +
                              "  Compiled XML files have these file extensions:\n" +
                              "  BND CLO DES EVF FOX2 FSD LAD PARTS PH PHSD SDF SIM TGT VDP VEH VFXLF\n" +
                              "Usage:\n" +
                              "  FoxTool [-d|-c] file_path|folder_path\n" +
                              "Examples:\n" +
                              "  FoxTool file_path.xml  - Compile the XML file\n" +
                              "  FoxTool -c file_path   - Compile the XML file\n" +
                              "  FoxTool file_path      - Decompile the file to XML\n" +
                              "  FoxTool -d file_path   - Decompile the file to XML\n" +
                              "  FoxTool folder_path    - Decompile all suitable files in the folder to XML\n" +
                              "  FoxTool -d folder_path - Decompile all suitable files in the folder to XML");
        }

        private static bool IsDecompilable(string fileExtension)
        {
            return DecompilableExtensions.Contains(fileExtension, StringComparer.OrdinalIgnoreCase);
        }

        private static void DecompileFile(string path)
        {
            try
            {
                Console.WriteLine("Reading dictionary");
                ReadGlobalHashNameDictionary();
            }
            catch (Exception e)
            {
                Console.WriteLine("Error while reading the dictionary: {0}", e);
                Environment.ExitCode = 1;
                return;
            }

            if (File.Exists(path))
            {
                if (IsDecompilable(Path.GetExtension(path)) == false)
                {
                    ShowNotDecompilableError();
                    return;
                }

                var file = new FileInfo(path);
                Console.WriteLine("Decompiling {0}", file.FullName);
                try
                {
                    DecompileFile(file);
                }
                catch (Exception e)
                {
                    Console.WriteLine("Error decompiling {0}: {1}", path, e);
                }
            }
            else if (Directory.Exists(path))
            {
                foreach (var file in GetFileList(new DirectoryInfo(path), true, DecompilableExtensions))
                {
                    Console.WriteLine("Decompiling {0}", file.FullName);
                    try
                    {
                        DecompileFile(file);
                    }
                    catch (Exception e)
                    {
                        Console.WriteLine("Error decompiling {0}: {1}", path, e);
                    }
                }
            }
            else
            {
                ShowUsageInfo();
            }
        }

        private static void ShowNotDecompilableError()
        {
            Console.WriteLine("The provided file is not decompilable.");
        }

        private static void DecompileFile(FileInfo file)
        {
            string fileName = string.Format("{0}.xml", Path.GetFileName(file.Name));
            string outputName = Path.Combine(file.DirectoryName, fileName);
            string temporaryName = outputName + ".tmp";
            try
            {
                using (FileStream input = new FileStream(file.FullName, FileMode.Open, FileAccess.Read, FileShare.Read))
                using (FileStream output = new FileStream(temporaryName, FileMode.Create))
                {
                    FoxLookupTable lookupTable = new FoxLookupTable(GlobalHashNameDictionary);
                    var foxFile = FoxFile.ReadFoxFile(input, lookupTable);
                    FoxConverter.DecompileFox(foxFile, output);
                }

                File.Move(temporaryName, outputName, true);
            }
            catch (Exception e)
            {
                Console.WriteLine("Error decompiling {0}: {1}", file.FullName, e);
                ReportFailure(temporaryName);
            }
        }

        private static List<FileInfo> GetFileList(DirectoryInfo fileDirectory, bool recursively, List<string> extensions)
        {
            List<FileInfo> files = new List<FileInfo>();
            if (recursively)
            {
                foreach (var directory in fileDirectory.GetDirectories())
                {
                    files.AddRange(GetFileList(directory, recursively, extensions));
                }
            }
            files.AddRange(
                fileDirectory.GetFiles()
                    .Where(f => extensions.Contains(f.Extension, StringComparer.CurrentCultureIgnoreCase)));
            return files;
        }

        private static void ReadGlobalHashNameDictionary()
        {
            // Assembly.Location comes back empty inside a single-file build, so ask the
            // runtime where the app lives instead. The dictionary sits right next to it.
            string executingAssemblyLocation = AppContext.BaseDirectory;
            string path = Path.Combine(executingAssemblyLocation, "fox_dictionary.txt");
            foreach (var line in File.ReadAllLines(path))
            {
                ulong hash = Hashing.HashString(line);
                if (GlobalHashNameDictionary.ContainsKey(hash) == false)
                {
                    GlobalHashNameDictionary.Add(hash, line);
                }
            }
        }
    }
}
