//
// PES Archive Tool: a small macOS drop window around the GzsTool and FoxTool command line tools.
//
// Drop .fpk / .fpkd files (or folders that contain them) onto the window and each
// archive is unpacked into a folder right next to it. Drop the .fpk.xml / .fpkd.xml
// file that unpacking left behind and the archive is rebuilt from that folder.
// .fox2 files work the same way: drop one to get a readable .fox2.xml, drop that xml
// to turn it back into a .fox2 file. A .fox2 file is only touched when it is dropped
// itself, never because it sits inside a dropped folder.
//
// Every drop does exactly what `GzsTool some_file` or `FoxTool some_file` would do in a terminal.
//
// The whole app lives in this one file so it can be built with a plain `swiftc`
// call (see build-macos.sh). No Xcode project needed.
//

import AppKit

// MARK: - Talking to the command line tools

/// One thing to do for one dropped file.
enum Job {
    /// Unpack an .fpk / .fpkd archive into a folder (GzsTool).
    case extract(URL)
    /// Rebuild an archive from its .fpk.xml / .fpkd.xml file and the folder next to it (GzsTool).
    case repack(URL)
    /// Turn a .fox2 file into readable xml (FoxTool).
    case decompile(URL)
    /// Turn a .fox2.xml file back into a .fox2 file (FoxTool).
    case compile(URL)
}

/// How a job went.
struct JobResult {
    /// The file that was dropped.
    let source: URL
    /// What it produced: a folder, an archive, an xml file or a .fox2 file.
    let product: URL
    let succeeded: Bool
    let summary: String
    let problem: String
}

enum Tool {
    static let archiveExtensions: Set<String> = ["fpk", "fpkd"]
    static let foxExtensions: Set<String> = ["fox2"]

    /// Both command line tools travel inside the app bundle (Contents/Resources),
    /// together with their dictionary files.
    static let binaryNames = ["GzsTool", "FoxTool"]

    static func binary(named name: String) -> URL? {
        return Bundle.main.url(forResource: name, withExtension: nil)
    }

    static func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    /// True for names like "stadium.fpk.xml": an xml file that belongs to one of the given file types.
    private static func isXML(_ url: URL, for extensions: Set<String>) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return extensions.contains(where: { name.hasSuffix("." + $0 + ".xml") })
    }

    /// What dropping this one file means. Nil if it is not a file we deal with.
    static func job(forFile url: URL) -> Job? {
        let fileExtension = url.pathExtension.lowercased()
        if archiveExtensions.contains(fileExtension) { return .extract(url) }
        if foxExtensions.contains(fileExtension) { return .decompile(url) }
        if isXML(url, for: archiveExtensions) { return .repack(url) }
        if isXML(url, for: foxExtensions) { return .compile(url) }
        return nil
    }

    /// Turns whatever was dropped into a list of jobs.
    ///
    /// Folders are searched all the way down, but only for .fpk / .fpkd archives to unpack.
    /// Everything else is strictly hands-on: a .fox2 file is only converted, and an xml file
    /// only repacked, when that very file is dropped. Unpacked archives often contain .fox2
    /// files, and those should stay as they are until someone asks for them.
    static func jobs(for urls: [URL]) -> [Job] {
        var list: [Job] = []
        for url in urls {
            if isFolder(url) {
                guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else {
                    continue
                }
                for case let child as URL in walker where !isFolder(child) {
                    guard let found = Tool.job(forFile: child) else { continue }
                    switch found {
                    case .extract: list.append(found)
                    case .decompile, .repack, .compile: break
                    }
                }
            } else if let found = Tool.job(forFile: url) {
                list.append(found)
            }
        }
        return list
    }

    /// GzsTool pairs "stadium.fpk" with the folder "stadium_fpk" right next to it.
    static func contentFolder(for archive: URL) -> URL {
        let name = archive.deletingPathExtension().lastPathComponent + "_" + archive.pathExtension
        return archive.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
    }

    /// Where a repack will write its archive. The name comes from the xml itself (that is what
    /// GzsTool goes by), with the xml's file name as the fallback.
    static func archive(describedBy xml: URL) -> URL {
        let folder = xml.deletingLastPathComponent()
        if let document = try? XMLDocument(contentsOf: xml, options: []),
           let name = document.rootElement()?.attribute(forName: "Name")?.stringValue,
           !name.isEmpty {
            return folder.appendingPathComponent(name)
        }
        return xml.deletingPathExtension()
    }

    /// Does one job and waits for it. Call this off the main thread.
    static func perform(_ job: Job) -> JobResult {
        switch job {
        case .extract(let archive):
            let outcome = run("GzsTool", on: archive)
            // The tool prints one line per unpacked file.
            let count = outcome.lines.filter { !$0.hasPrefix("Error reading") }.count
            let files = count == 1 ? "1 file" : "\(count) files"
            return JobResult(source: archive, product: contentFolder(for: archive),
                             succeeded: outcome.succeeded, summary: "unpacked, " + files, problem: outcome.problem)

        case .repack(let xml):
            let archive = Tool.archive(describedBy: xml)
            let folder = contentFolder(for: archive)
            // Check before starting, so a missing folder is reported in plain words.
            guard isFolder(folder) else {
                return JobResult(source: xml, product: archive, succeeded: false, summary: "",
                                 problem: "The folder \"\(folder.lastPathComponent)\" has to sit next to the xml file.")
            }
            let outcome = run("GzsTool", on: xml)
            return JobResult(source: xml, product: archive,
                             succeeded: outcome.succeeded, summary: "repacked", problem: outcome.problem)

        case .decompile(let foxFile):
            // FoxTool writes "scene.fox2.xml" next to "scene.fox2".
            let outcome = run("FoxTool", on: foxFile)
            return JobResult(source: foxFile, product: foxFile.appendingPathExtension("xml"),
                             succeeded: outcome.succeeded, summary: "unpacked to xml", problem: outcome.problem)

        case .compile(let xml):
            // ...and "scene.fox2.xml" becomes "scene.fox2" again.
            let outcome = run("FoxTool", on: xml)
            return JobResult(source: xml, product: xml.deletingPathExtension(),
                             succeeded: outcome.succeeded, summary: "repacked", problem: outcome.problem)
        }
    }

    /// Runs `<tool> <file>`. Both tools work out from the file name whether to unpack or repack.
    private static func run(_ toolName: String, on file: URL) -> (succeeded: Bool, lines: [String], problem: String) {
        guard let tool = binary(named: toolName) else {
            return (false, [], toolName + " is missing from the app bundle. Run build-macos.sh again.")
        }

        let process = Process()
        process.executableURL = tool
        process.arguments = [file.path]

        // One pipe for both streams keeps things simple: we only want the text.
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return (false, [], error.localizedDescription)
        }

        // Read first, then wait. The other way round can stall once the pipe fills up.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let text = String(data: data, encoding: .utf8) ?? ""
        let lines = text.split(whereSeparator: { $0.isNewline }).map { String($0) }

        if process.terminationStatus != 0 {
            // A failure prints a long stack trace. The line naming the exception says the most.
            let headline = lines.first(where: { $0.lowercased().contains("exception") })
                ?? lines.last
                ?? toolName + " stopped unexpectedly."
            return (false, lines, headline)
        }
        return (true, lines, "")
    }
}

// MARK: - The drop area

final class DropView: NSView {
    /// Called with the dropped (or picked) files and folders.
    var onFiles: (([URL]) -> Void)?
    /// Called when the area is clicked, as an alternative to dragging.
    var onClick: (() -> Void)?

    private var isTargeted = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        buildLabels()
    }

    required init?(coder: NSCoder) {
        fatalError("This view is only ever created in code.")
    }

    private func buildLabels() {
        let icon = NSImageView()
        if let symbol = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil) {
            icon.image = symbol
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 34, weight: .light)
        }
        icon.contentTintColor = .secondaryLabelColor

        let title = NSTextField(labelWithString: "Drop .fpk / .fpkd / .fox2 files to unpack")
        title.font = .systemFont(ofSize: 17, weight: .semibold)

        let hint = NSTextField(labelWithString: "Drop the .xml file that unpacking created to repack.")
        let secondHint = NSTextField(labelWithString: "Folders are searched for .fpk / .fpkd only. Or click to choose files.")
        for label in [hint, secondHint] {
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
        }

        let stack = NSStackView(views: [icon, title, hint, secondHint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16)
        ])
    }

    // The labels are decoration only. Clicks anywhere inside should land on the drop area itself.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return super.hitTest(point) == nil ? nil : self
    }

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 14, yRadius: 14)

        if isTargeted {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            outline.fill()
        }

        let dashes: [CGFloat] = [8, 6]
        outline.setLineDash(dashes, count: dashes.count, phase: 0)
        outline.lineWidth = 2
        (isTargeted ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).setStroke()
        outline.stroke()
    }

    // MARK: Dragging

    private func fileURLs(from info: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options)
        return objects as? [URL] ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Only light up when there is something in the drag we can actually work with.
        // Folders get the benefit of the doubt, searching them here would make the drag stutter.
        let urls = fileURLs(from: sender)
        let usable = urls.contains(where: { Tool.isFolder($0) || Tool.job(forFile: $0) != nil })
        isTargeted = usable
        return usable ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isTargeted = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isTargeted = false
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onFiles?(urls)
        return true
    }
}

// MARK: - The app

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum Tone {
        case plain, good, bad, quiet
    }

    private static let revealKey = "revealWhenDone"

    private var window: NSWindow!
    private var logView: NSTextView!
    private let dropView = DropView(frame: .zero)
    private let statusLabel = NSTextField(labelWithString: "Ready")
    private let spinner = NSProgressIndicator()
    private let revealCheckbox = NSButton(checkboxWithTitle: "Show in Finder when done", target: nil, action: nil)

    /// Jobs run one after another, away from the main thread, so the window stays responsive.
    private let workQueue = DispatchQueue(label: "pesarchivetool.jobs")
    private var remaining = 0

    // Files can arrive before the window exists (dropping onto the Dock icon launches the app).
    private var filesWaitingForWindow: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [AppDelegate.revealKey: true])
        buildMenu()
        buildWindow()

        for name in Tool.binaryNames where Tool.binary(named: name) == nil {
            log(name + " is missing from the app bundle. Run build-macos.sh again.", .bad)
        }

        let waiting = filesWaitingForWindow
        filesWaitingForWindow = []
        if !waiting.isEmpty {
            handle(waiting)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    /// Files dropped onto the Dock icon, or opened with "Open With", end up here.
    func application(_ application: NSApplication, open urls: [URL]) {
        if window == nil {
            filesWaitingForWindow.append(contentsOf: urls)
        } else {
            handle(urls)
        }
    }

    // MARK: Building the interface

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Hide PES Archive Tool", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit PES Archive Tool", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let openItem = NSMenuItem(title: "Open…", action: #selector(chooseFiles), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(openItem)
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        NSApp.mainMenu = mainMenu
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "PES Archive Tool"
        window.minSize = NSSize(width: 500, height: 360)
        window.isReleasedWhenClosed = false

        let content = NSView()
        window.contentView = content

        dropView.onFiles = { [weak self] urls in self?.handle(urls) }
        dropView.onClick = { [weak self] in self?.chooseFiles() }

        // The log: one line per archive, plus anything that went wrong.
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .bezelBorder
        logView = (scrollView.documentView as! NSTextView)
        logView.isEditable = false
        logView.textContainerInset = NSSize(width: 6, height: 6)

        revealCheckbox.target = self
        revealCheckbox.action = #selector(revealChoiceChanged)
        revealCheckbox.state = UserDefaults.standard.bool(forKey: AppDelegate.revealKey) ? .on : .off

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .right

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        let views: [NSView] = [dropView, scrollView, revealCheckbox, statusLabel, spinner]
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }

        NSLayoutConstraint.activate([
            dropView.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            dropView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            dropView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            dropView.heightAnchor.constraint(equalToConstant: 170),

            scrollView.topAnchor.constraint(equalTo: dropView.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: dropView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: dropView.trailingAnchor),

            revealCheckbox.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 10),
            revealCheckbox.leadingAnchor.constraint(equalTo: dropView.leadingAnchor),
            revealCheckbox.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),

            statusLabel.centerYAnchor.constraint(equalTo: revealCheckbox.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: dropView.trailingAnchor),

            spinner.centerYAnchor.constraint(equalTo: revealCheckbox.centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: statusLabel.leadingAnchor, constant: -6),
            spinner.leadingAnchor.constraint(greaterThanOrEqualTo: revealCheckbox.trailingAnchor, constant: 12)
        ])

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Actions

    @objc private func revealChoiceChanged() {
        UserDefaults.standard.set(revealCheckbox.state == .on, forKey: AppDelegate.revealKey)
    }

    @objc private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.message = "Choose .fpk / .fpkd / .fox2 files to unpack, or their .xml files to repack"
        panel.prompt = "Go"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK {
                self?.handle(panel.urls)
            }
        }
    }

    // MARK: Unpacking and repacking

    private func handle(_ urls: [URL]) {
        let jobs = Tool.jobs(for: urls)
        guard !jobs.isEmpty else {
            log("Nothing to do with that drop. Unpacking takes .fpk / .fpkd / .fox2 files, repacking takes their .xml files. In folders only .fpk / .fpkd are picked up.", .quiet)
            return
        }

        remaining += jobs.count
        updateStatus()

        workQueue.async {
            var products: [URL] = []
            for job in jobs {
                let result = Tool.perform(job)
                if result.succeeded {
                    products.append(result.product)
                }
                DispatchQueue.main.async {
                    self.report(result)
                }
            }
            let finished = products
            DispatchQueue.main.async {
                self.batchFinished(finished)
            }
        }
    }

    private func report(_ result: JobResult) {
        let name = result.source.lastPathComponent
        if result.succeeded {
            log("✓ \(name)  →  \(result.product.lastPathComponent)  (\(result.summary))", .good)
        } else {
            log("✗ \(name)  failed", .bad)
            log("    \(result.problem)", .quiet)
        }
        remaining -= 1
        updateStatus()
    }

    private func batchFinished(_ products: [URL]) {
        let reveal = UserDefaults.standard.bool(forKey: AppDelegate.revealKey)
        if reveal && !products.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(products)
        }
    }

    private func updateStatus() {
        if remaining > 0 {
            statusLabel.stringValue = remaining == 1 ? "Working, 1 file left" : "Working, \(remaining) files left"
            spinner.startAnimation(nil)
        } else {
            statusLabel.stringValue = "Done"
            spinner.stopAnimation(nil)
        }
    }

    private func log(_ message: String, _ tone: Tone) {
        let color: NSColor
        switch tone {
        case .plain: color = .labelColor
        case .good: color = .systemGreen
        case .bad: color = .systemRed
        case .quiet: color = .secondaryLabelColor
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular),
            .foregroundColor: color
        ]
        logView.textStorage?.append(NSAttributedString(string: message + "\n", attributes: attributes))
        logView.scrollToEndOfDocument(nil)
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
