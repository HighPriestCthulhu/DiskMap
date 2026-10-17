import SwiftUI

struct ContentView: View {
    @ObservedObject var model: Model

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ZStack {
                Color(white: 0.1)
                if model.scanning {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Scanning…").font(.headline)
                        Text(model.progressText)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle).padding(.horizontal, 30)
                        Button("Cancel") { model.cancelScan() }
                    }
                } else if model.viewRoot == nil {
                    welcome
                } else {
                    TreemapView(model: model)
                }
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 700, minHeight: 450)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Choose Folder…") { model.chooseFolder() }.keyboardShortcut("o")
                Button("Home Folder") { model.startScan(FileManager.default.homeDirectoryForCurrentUser) }
                Button("Entire Disk (Macintosh HD)") { model.startScan(URL(fileURLWithPath: "/System/Volumes/Data")) }
            } label: { Label("Scan", systemImage: "externaldrive") }
            .fixedSize()

            Button { model.zoomOut() } label: { Image(systemName: "arrow.up.left") }
                .help("Up one level (Esc)")
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(model.viewRoot?.parent == nil)
            Button { model.rescan() } label: { Image(systemName: "arrow.clockwise") }
                .help("Rescan").keyboardShortcut("r")
                .disabled(model.root == nil || model.scanning)

            Divider().frame(height: 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(model.breadcrumbs.enumerated()), id: \.offset) { i, n in
                        if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                        let label = i == 0 ? n.name : n.name
                        Button(label) { model.zoomTo(n) }
                            .buttonStyle(.plain)
                            .foregroundStyle(n === model.viewRoot ? .primary : .secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private var welcome: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.3x3.fill").font(.system(size: 46)).foregroundStyle(.secondary)
            Text("See what's using your disk").font(.title2)
            HStack {
                Button("Choose Folder…") { model.chooseFolder() }
                Button("Scan Home") { model.startScan(FileManager.default.homeDirectoryForCurrentUser) }
                Button("Scan Entire Disk") { model.startScan(URL(fileURLWithPath: "/System/Volumes/Data")) }
            }
            Text("Tip: grant Full Disk Access in System Settings → Privacy & Security for complete results.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
    }

    private var statusBar: some View {
        HStack {
            if let n = model.hovered ?? model.selected, let v = model.viewRoot {
                let pct = v.size > 0 ? Double(n.size) / Double(v.size) * 100 : 0
                Text(n.path).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("\(formatBytes(n.size)) · \(String(format: "%.1f", pct))%" + (n.isDir ? " · \(n.itemCount.formatted()) files" : ""))
                    .monospacedDigit()
            } else if let v = model.viewRoot {
                Text(v.path).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("\(formatBytes(v.size)) · \(v.itemCount.formatted()) files").monospacedDigit()
            } else {
                Text("No scan yet").foregroundStyle(.secondary)
                Spacer()
            }
        }
        .font(.caption)
        .padding(.horizontal, 10).padding(.vertical, 4)
    }
}

struct TreemapView: View {
    @ObservedObject var model: Model

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in draw(ctx) }
                .onAppear { model.setCanvasSize(geo.size) }
                .onChange(of: geo.size) { model.setCanvasSize($0) }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p): model.hovered = model.hit(p)
                    case .ended: model.hovered = nil
                    }
                }
                .gesture(SpatialTapGesture(count: 2).onEnded { model.zoomIn(model.hit($0.location)) })
                .simultaneousGesture(SpatialTapGesture().onEnded { model.selected = model.hit($0.location) })
                .contextMenu {
                    if let n = model.hovered {
                        Button("Reveal in Finder") { model.reveal(n) }
                        Button("Open") { model.open(n) }
                        Button("Copy Path") { model.copyPath(n) }
                        if n.isDir && !n.children.isEmpty { Button("Zoom Into Folder") { model.zoomIn(n) } }
                        if !n.isAggregate && n.parent != nil {
                            Divider()
                            Button("Move to Trash…", role: .destructive) { model.trash(n) }
                        }
                    }
                }
        }
    }

    private func draw(_ ctx: GraphicsContext) {
        let selected = model.selected, hovered = model.hovered
        for t in model.tiles {
            let r = t.rect, n = t.node
            if t.depth == 0 {
                ctx.fill(Path(r), with: .color(Palette.containerColor(depth: 0)))
                continue
            }
            let path = Path(r)
            if t.isContainer {
                ctx.fill(path, with: .color(Palette.containerColor(depth: t.depth)))
                label(ctx, n, r, header: true)
            } else if n.isDir {
                ctx.fill(path, with: .color(Palette.collapsedFolder))
                label(ctx, n, r, header: false)
            } else {
                let c = Palette.fileColor(n)
                ctx.fill(path, with: .linearGradient(
                    Gradient(colors: [c, c.opacity(0.72)]),
                    startPoint: r.origin, endPoint: CGPoint(x: r.maxX, y: r.maxY)))
                label(ctx, n, r, header: false)
            }
            ctx.stroke(Path(r.insetBy(dx: 0.25, dy: 0.25)), with: .color(.black.opacity(0.45)), lineWidth: 0.5)
        }
        for (n, color, width) in [(hovered, Color.white.opacity(0.7), 1.0), (selected, Color.white, 2.0)] {
            if let n, let t = model.tiles.first(where: { $0.node === n }) {
                ctx.stroke(Path(t.rect.insetBy(dx: width / 2, dy: width / 2)), with: .color(color), lineWidth: width)
            }
        }
    }

    private func label(_ ctx: GraphicsContext, _ n: Node, _ r: CGRect, header: Bool) {
        let h = header ? Treemap.headerHeight : r.height
        guard r.width > 36, h >= 13 else { return }
        let showSize = r.width > 90 && (header || r.height > 30)
        let text = showSize ? "\(n.name)  \(formatBytes(n.size))" : n.name
        let resolved = ctx.resolve(Text(text).font(.system(size: 10, weight: header ? .semibold : .regular)).foregroundColor(.white))
        let clip = CGRect(x: r.minX, y: r.minY, width: r.width, height: header ? h : r.height)
        ctx.drawLayer { l in
            l.clip(to: Path(clip))
            l.draw(resolved, at: CGPoint(x: r.minX + 4, y: r.minY + 2), anchor: .topLeading)
        }
    }
}
