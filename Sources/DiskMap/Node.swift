import Foundation

/// One file or folder in the scanned tree. Folders own their children; children point back unowned.
final class Node {
    let name: String
    var size: Int64
    let isDir: Bool
    var isAggregate = false
    var children: [Node] = []
    var itemCount = 0
    unowned(unsafe) var parent: Node? = nil

    init(name: String, isDir: Bool, size: Int64 = 0) {
        self.name = name
        self.isDir = isDir
        self.size = size
    }

    var path: String {
        guard let p = parent else { return name }
        let pp = p.path
        return pp == "/" ? "/" + name : pp + "/" + name
    }

    var url: URL { URL(fileURLWithPath: path) }
}

func formatBytes(_ n: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
}
