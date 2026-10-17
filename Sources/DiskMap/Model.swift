import SwiftUI
import AppKit

@MainActor
final class Model: ObservableObject {
    @Published var root: Node?
    @Published var viewRoot: Node?
    @Published var selected: Node?
    @Published var hovered: Node?
    @Published var tiles: [Tile] = []
    @Published var scanning = false
    @Published var progressText = ""

    private var canvasSize: CGSize = .zero
    private var progress: ScanProgress?
    private var timer: Timer?

    // MARK: Scanning

    func startScan(_ url: URL) {
        progress?.cancelled = true
        let p = ScanProgress()
        progress = p
        scanning = true
        root = nil; viewRoot = nil; selected = nil; hovered = nil; tiles = []
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.scanning else { return }
                let s = p.snapshot
                self.progressText = "\(s.items.formatted()) files · \(formatBytes(s.bytes)) — \(s.current)"
            }
        }
        let path = url.path
        DispatchQueue.global(qos: .userInitiated).async {
            let node = DiskScanner.scan(root: path, progress: p)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.progress === p, !p.cancelled else { return }
                self.timer?.invalidate()
                self.scanning = false
                self.root = node
                self.viewRoot = node
                self.relayout()
            }
        }
    }

    func cancelScan() {
        progress?.cancelled = true
        timer?.invalidate()
        scanning = false
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Scan"
        if panel.runModal() == .OK, let url = panel.url { startScan(url) }
    }

    func rescan() {
        if let r = root { startScan(URL(fileURLWithPath: r.name)) }
    }

    // MARK: Layout & navigation

    func setCanvasSize(_ size: CGSize) {
        guard size != canvasSize else { return }
        canvasSize = size
        relayout()
    }

    func relayout() {
        guard let v = viewRoot, canvasSize.width > 1, canvasSize.height > 1 else { tiles = []; return }
        tiles = Treemap.layout(root: v, size: canvasSize)
    }

    func hit(_ p: CGPoint) -> Node? {
        // Tiles are emitted parent-first, so the last match is the deepest.
        tiles.last(where: { $0.rect.contains(p) })?.node
    }

    func zoomIn(_ n: Node?) {
        guard let n, n.isDir, !n.children.isEmpty else { return }
        viewRoot = n; selected = nil; hovered = nil
        relayout()
    }

    func zoomOut() {
        guard let v = viewRoot, let p = v.parent else { return }
        viewRoot = p; selected = v
        relayout()
    }

    func zoomTo(_ n: Node) {
        viewRoot = n; selected = nil
        relayout()
    }

    var breadcrumbs: [Node] {
        var chain: [Node] = []
        var n = viewRoot
        while let c = n { chain.insert(c, at: 0); n = c.parent }
        return chain
    }

    // MARK: Actions on a node

    func reveal(_ n: Node) { NSWorkspace.shared.activateFileViewerSelecting([n.url]) }
    func open(_ n: Node) { NSWorkspace.shared.open(n.url) }

    func copyPath(_ n: Node) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(n.path, forType: .string)
    }

    func trash(_ n: Node) {
        guard !n.isAggregate, let parent = n.parent else { return }
        let path = n.path
        let alert = NSAlert()
        alert.messageText = "Move “\(n.name)” to the Trash?"
        alert.informativeText = "\(path)\n\n\(formatBytes(n.size)) will be moved to the Trash. You can restore it from there."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // The tree is a snapshot: make sure the path still names the same kind of item, and not a symlink.
        guard Self.stillMatches(n, at: path) else {
            let changed = NSAlert()
            changed.messageText = "This item changed since the scan — rescan and try again."
            changed.informativeText = path
            changed.alertStyle = .warning
            changed.runModal()
            return
        }
        do {
            try FileManager.default.trashItem(at: n.url, resultingItemURL: nil)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        let removed = n.size, removedItems = n.isDir ? n.itemCount : 1
        parent.children.removeAll { $0 === n }
        var a: Node? = parent
        while let c = a { c.size -= removed; c.itemCount -= removedItems; a = c.parent }
        selected = nil; hovered = nil
        relayout()
    }

    /// True if `path` still exists, is not a symlink, and is a folder/file exactly when the node is.
    private static func stillMatches(_ n: Node, at path: String) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0 else { return false }
        let type = st.st_mode & S_IFMT
        if type == S_IFLNK { return false }
        return n.isDir ? type == S_IFDIR : type == S_IFREG
    }
}
