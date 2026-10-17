import SwiftUI

struct Tile {
    let node: Node
    let rect: CGRect
    let depth: Int
    let isContainer: Bool   // folder whose children are drawn inside it
}

enum Treemap {
    static let headerHeight: CGFloat = 15
    static let minContainer: CGFloat = 26

    static func layout(root: Node, size: CGSize) -> [Tile] {
        var out: [Tile] = []
        func place(_ n: Node, _ r: CGRect, _ depth: Int) {
            let canNest = n.isDir && !n.children.isEmpty && r.width > minContainer && r.height > minContainer
            out.append(Tile(node: n, rect: r, depth: depth, isContainer: canNest))
            guard canNest else { return }
            let header: CGFloat = depth == 0 ? 0 : headerHeight
            let pad: CGFloat = depth == 0 ? 0 : 2
            let inner = CGRect(x: r.minX + pad, y: r.minY + header, width: r.width - 2 * pad, height: r.height - header - pad)
            guard inner.width > 4, inner.height > 4 else { return }
            for (child, cr) in squarify(n.children, in: inner) where cr.width >= 2 && cr.height >= 2 {
                place(child, cr, depth + 1)
            }
        }
        place(root, CGRect(origin: .zero, size: size), 0)
        return out
    }

    /// Squarified treemap (Bruls et al.): rows of items laid along the shorter side, keeping tiles near-square.
    static func squarify(_ items: [Node], in bounds: CGRect) -> [(Node, CGRect)] {
        let items = items.filter { $0.size > 0 }
        var remaining = items.reduce(Int64(0)) { $0 + $1.size }
        guard remaining > 0 else { return [] }
        var rect = bounds
        var result: [(Node, CGRect)] = []
        var i = 0
        while i < items.count, rect.width > 0, rect.height > 0 {
            let scale = Double(rect.width * rect.height) / Double(remaining)
            let side = Double(min(rect.width, rect.height))
            var end = i
            var rowSum: Int64 = 0
            var best = Double.infinity
            while end < items.count {
                let s = rowSum + items[end].size
                let area = Double(s) * scale
                let maxA = Double(items[i].size) * scale
                let minA = Double(items[end].size) * scale
                let worst = max(side * side * maxA / (area * area), area * area / (side * side * minA))
                if end > i && worst > best { break }
                best = worst; rowSum = s; end += 1
            }
            let rowArea = Double(rowSum) * scale
            if rect.width >= rect.height {
                let w = CGFloat(rowArea / Double(rect.height))
                var y = rect.minY
                for k in i..<end {
                    let h = CGFloat(Double(items[k].size) * scale / Double(w))
                    result.append((items[k], CGRect(x: rect.minX, y: y, width: w, height: h)))
                    y += h
                }
                rect = CGRect(x: rect.minX + w, y: rect.minY, width: max(0, rect.width - w), height: rect.height)
            } else {
                let h = CGFloat(rowArea / Double(rect.width))
                var x = rect.minX
                for k in i..<end {
                    let w = CGFloat(Double(items[k].size) * scale / Double(h))
                    result.append((items[k], CGRect(x: x, y: rect.minY, width: w, height: h)))
                    x += w
                }
                rect = CGRect(x: rect.minX, y: rect.minY + h, width: rect.width, height: max(0, rect.height - h))
            }
            remaining -= rowSum
            i = end
        }
        return result
    }
}

enum Palette {
    private static let groups: [(hue: Double, exts: Set<String>)] = [
        (0.78, ["jpg", "jpeg", "png", "gif", "heic", "heif", "tiff", "tif", "bmp", "raw", "cr2", "nef", "arw", "dng", "psd", "svg", "webp", "ai"]),
        (0.00, ["mov", "mp4", "m4v", "avi", "mkv", "wmv", "webm", "mpg", "mpeg", "prores"]),
        (0.07, ["mp3", "m4a", "wav", "aiff", "aif", "flac", "aac", "ogg", "caf", "band"]),
        (0.14, ["zip", "gz", "tgz", "tar", "bz2", "xz", "7z", "rar", "pkg", "xip"]),
        (0.58, ["pdf", "doc", "docx", "pages", "txt", "rtf", "md", "xls", "xlsx", "numbers", "csv", "ppt", "pptx", "key"]),
        (0.36, ["swift", "m", "h", "c", "cpp", "js", "ts", "py", "rb", "go", "rs", "java", "json", "xml", "html", "css", "plist", "o", "a", "swiftmodule", "pyc"]),
        (0.48, ["dylib", "so", "framework", "app", "exe", "dll", "bin", "car", "nib", "strings", "lproj", "mlmodel", "mlmodelc"]),
        (0.09, ["dmg", "iso", "img", "vmdk", "vdi", "qcow2", "sparseimage", "sparsebundle", "photoslibrary"]),
        (0.92, ["db", "sqlite", "sqlite3", "log", "cache", "tmp"]),
    ]
    private static let lookup: [String: Double] = {
        var d: [String: Double] = [:]
        for g in groups { for e in g.exts { d[e] = g.hue } }
        return d
    }()

    static func fileColor(_ n: Node) -> Color {
        if n.isAggregate { return Color(hue: 0, saturation: 0, brightness: 0.45) }
        let ext = (n.name as NSString).pathExtension.lowercased()
        if let h = lookup[ext] { return Color(hue: h, saturation: 0.55, brightness: 0.78) }
        return Color(hue: 0.62, saturation: 0.12, brightness: 0.62)
    }

    static func containerColor(depth: Int) -> Color {
        Color(hue: 0.60, saturation: 0.22, brightness: depth % 2 == 0 ? 0.22 : 0.30)
    }

    static let collapsedFolder = Color(hue: 0.60, saturation: 0.45, brightness: 0.50)
}
