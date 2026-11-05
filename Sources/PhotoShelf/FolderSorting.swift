import SwiftUI
import PhotoLibraryCore

extension LibraryModel {
    func folderKey(_ source: UUID, _ path: String) -> String { source.uuidString + "|" + path }
    private func parentKey(_ source: UUID, _ path: String) -> String {
        path.isEmpty ? "sources" : folderKey(source, (path as NSString).deletingLastPathComponent)
    }
    private func creationDate(_ source: UUID, _ path: String) -> Date {
        let key = folderKey(source, path)
        if let date = folderCreationCache[key] { return date }
        guard let root = snapshot.sources.first(where: { $0.id == source }) else { return .distantPast }
        let url = URL(fileURLWithPath: root.path).appendingPathComponent(path)
        let date = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
        folderCreationCache[key] = date
        return date
    }
    func folderPrecedes(source a: UUID, path ap: String, name an: String, source b: UUID, path bp: String, name bn: String) -> Bool {
        if folderSort == "manual" {
            let order = folderOrder[parentKey(a, ap)] ?? []
            let ai = order.firstIndex(of: folderKey(a, ap)) ?? Int.max
            let bi = order.firstIndex(of: folderKey(b, bp)) ?? Int.max
            if ai != bi { return ai < bi }
        }
        if folderSort.hasPrefix("created") {
            let ad = creationDate(a, ap), bd = creationDate(b, bp)
            if ad != bd { return folderSort == "createdDescending" ? ad > bd : ad < bd }
        }
        let comparison = an.localizedStandardCompare(bn)
        if comparison != .orderedSame { return folderSort == "nameDescending" ? comparison == .orderedDescending : comparison == .orderedAscending }
        return folderKey(a, ap) < folderKey(b, bp)
    }
    var sortedSources: [PhotoSource] {
        activeSources.sorted { folderPrecedes(source: $0.id, path: "", name: $0.name, source: $1.id, path: "", name: $1.name) }
    }
    func sortedFolders(_ nodes: [FolderNode], source: UUID) -> [FolderNode] {
        nodes.sorted { folderPrecedes(source: source, path: $0.path, name: $0.name, source: source, path: $1.path, name: $1.name) }
    }
    func reorderFolder(_ token: String, before source: UUID, path: String) -> Bool {
        guard token.hasPrefix("photoshelf-folder:"), folderSort == "manual" else { return false }
        let parts = token.dropFirst("photoshelf-folder:".count).split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let from = UUID(uuidString: String(parts[0])) else { return false }
        let fromPath = String(parts[1]), group = parentKey(source, path)
        guard parentKey(from, fromPath) == group else { return false }
        var keys: [String]
        if path.isEmpty { keys = sortedSources.map { folderKey($0.id, "") } }
        else {
            func siblings(_ nodes: [FolderNode]) -> [FolderNode]? {
                if nodes.contains(where: { $0.path == path }) { return nodes }
                for node in nodes { if let result = siblings(node.children) { return result } }
                return nil
            }
            guard let nodes = siblings(folderNodes[source] ?? []) else { return false }
            keys = sortedFolders(nodes, source: source).map { folderKey(source, $0.path) }
        }
        let moving = folderKey(from, fromPath), target = folderKey(source, path)
        guard moving != target, keys.contains(moving), keys.contains(target) else { return false }
        keys.removeAll { $0 == moving }
        keys.insert(moving, at: keys.firstIndex(of: target)!)
        folderOrder[group] = keys
        return true
    }
}

struct FolderSortMenu: View {
    @State private var hovered = false
    @EnvironmentObject private var model: LibraryModel
    var body: some View {
        Menu {
            Picker("文件夹排序", selection: $model.folderSort) {
                Text("手动拖拽排序").tag("manual")
                Text("名称：A → Z").tag("name")
                Text("名称：Z → A").tag("nameDescending")
                Text("创建时间：从新到旧").tag("createdDescending")
                Text("创建时间：从旧到新").tag("created")
            }.pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down").font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary).frame(width: 24, height: 24).contentShape(Rectangle())
                .background(hovered ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .tint(Color(nsColor: .secondaryLabelColor)).onHover { hovered = $0 }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("文件夹排序 · 手动模式可拖到同级文件夹前方").accessibilityLabel("文件夹排序")
    }
}

struct FolderReorder: ViewModifier {
    @EnvironmentObject private var model: LibraryModel
    let source: UUID
    let path: String
    @State private var targeted = false
    func body(content: Content) -> some View {
        content
            .onDrag { NSItemProvider(object: ("photoshelf-folder:" + model.folderKey(source, path)) as NSString) }
            .dropDestination(for: String.self) { items, _ in
                guard let item = items.first else { return false }
                return model.reorderFolder(item, before: source, path: path)
            } isTargeted: { targeted = $0 }
            .overlay(alignment: .top) {
                if targeted && model.folderSort == "manual" { Rectangle().fill(Color.primary.opacity(0.5)).frame(height: 2).allowsHitTesting(false) }
            }
    }
}
