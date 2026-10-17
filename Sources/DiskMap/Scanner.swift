import Foundation
import Darwin

/// Thread-safe counters the UI polls while a scan runs.
final class ScanProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var _items = 0
    private var _bytes: Int64 = 0
    private var _current = ""
    var cancelled = false

    func add(items: Int, bytes: Int64, current: String) {
        lock.lock(); _items += items; _bytes += bytes; _current = current; lock.unlock()
    }
    var snapshot: (items: Int, bytes: Int64, current: String) {
        lock.lock(); defer { lock.unlock() }
        return (_items, _bytes, _current)
    }
}

/// Fast scanner: getattrlistbulk returns name/type/size for a whole directory per syscall,
/// and every folder is its own task on a shared work queue (so one huge folder never serialises the scan).
final class DiskScanner: @unchecked Sendable {
    /// Max individual file nodes kept per folder; the rest are folded into one "N smaller files" tile.
    static let maxFilesPerFolder = 150

    private let progress: ScanProgress
    private let dev: dev_t
    private let queue = OperationQueue()
    private let group = DispatchGroup()

    private init(progress: ScanProgress, dev: dev_t) {
        self.progress = progress
        self.dev = dev
        queue.maxConcurrentOperationCount = max(8, ProcessInfo.processInfo.activeProcessorCount * 2)
        queue.qualityOfService = .userInitiated
    }

    static func scan(root path: String, progress: ScanProgress) -> Node {
        var st = stat()
        let dev: dev_t = lstat(path, &st) == 0 ? st.st_dev : 0
        let scanner = DiskScanner(progress: progress, dev: dev)
        let root = Node(name: path, isDir: true)
        scanner.spawn(path, root)
        scanner.group.wait()
        finalize(root)
        return root
    }

    private func spawn(_ path: String, _ node: Node) {
        group.enter()
        queue.addOperation { [self] in
            defer { group.leave() }
            if !progress.cancelled { scanOne(path, node) }
        }
    }

    private func scanOne(_ path: String, _ node: Node) {
        // Cloud-provider mounts (Google Drive, OneDrive, …) are network-backed: slow, and not local disk use.
        if path.hasSuffix("/Library/CloudStorage") { return }
        let fd = open(path, O_RDONLY | O_DIRECTORY)
        guard fd >= 0 else { return }
        defer { close(fd) }

        var al = attrlist()
        al.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        al.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME)
            | attrgroup_t(ATTR_CMN_DEVID) | attrgroup_t(ATTR_CMN_OBJTYPE)
        al.fileattr = attrgroup_t(ATTR_FILE_ALLOCSIZE)

        let bufSize = 256 * 1024
        let buf = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 8)
        defer { buf.deallocate() }

        var fileCount = 0
        var bytes: Int64 = 0
        var subdirs: [(String, Node)] = []

        while !progress.cancelled {
            let n = getattrlistbulk(fd, &al, buf, bufSize, 0)
            if n <= 0 { break }
            var p = UnsafeRawPointer(buf)
            for _ in 0..<Int(n) {
                let entryStart = p
                let length = Int(p.loadUnaligned(as: UInt32.self))
                var f = p + 4
                let returned = f.loadUnaligned(as: attribute_set_t.self)
                f += MemoryLayout<attribute_set_t>.size

                var name = ""
                if returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 {
                    let ref = f.loadUnaligned(as: attrreference_t.self)
                    name = String(cString: (f + Int(ref.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
                    f += MemoryLayout<attrreference_t>.size
                }
                var entryDev: UInt32 = UInt32(bitPattern: Int32(dev))
                if returned.commonattr & attrgroup_t(ATTR_CMN_DEVID) != 0 {
                    entryDev = f.loadUnaligned(as: UInt32.self); f += 4
                }
                var objType: UInt32 = 0
                if returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
                    objType = f.loadUnaligned(as: UInt32.self); f += 4
                }
                var alloc: Int64 = 0
                if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
                    alloc = f.loadUnaligned(as: Int64.self); f += 8
                }
                p = entryStart + length

                if objType == 2 {                                   // VDIR
                    if entryDev == UInt32(bitPattern: Int32(dev)) { // stay on one volume
                        let child = Node(name: name, isDir: true)
                        child.parent = node
                        node.children.append(child)
                        subdirs.append((path == "/" ? "/" + name : path + "/" + name, child))
                    }
                } else if objType == 1 {                            // VREG (symlinks etc. skipped)
                    let child = Node(name: name, isDir: false, size: alloc)
                    child.parent = node
                    node.children.append(child)
                    fileCount += 1
                    bytes += alloc
                }
            }
        }
        progress.add(items: fileCount, bytes: bytes, current: path)
        for (p, child) in subdirs { spawn(p, child) }
    }

    /// Post-order pass: fold tiny files, sum sizes, sort.
    private static func finalize(_ node: Node) {
        var files: [Node] = [], dirs: [Node] = []
        for c in node.children { if c.isDir { dirs.append(c) } else { files.append(c) } }
        for d in dirs { finalize(d) }
        files.sort { $0.size > $1.size }
        var items = files.count
        if files.count > maxFilesPerFolder {
            let rest = files[maxFilesPerFolder...]
            let agg = Node(name: "\(rest.count) smaller files", isDir: false, size: rest.reduce(0) { $0 + $1.size })
            agg.isAggregate = true
            agg.parent = node
            files = Array(files[..<maxFilesPerFolder]) + [agg]
        }
        var kids = files + dirs
        kids.sort { $0.size > $1.size }
        node.children = kids
        node.size = kids.reduce(0) { $0 + $1.size }
        items += dirs.reduce(0) { $0 + $1.itemCount }
        node.itemCount = items
    }
}
