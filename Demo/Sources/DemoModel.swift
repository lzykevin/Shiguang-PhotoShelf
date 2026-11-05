import SwiftUI
import AppKit

struct SamplePhoto: Identifiable {
    let id: Int
    let title: String
    let collection: String
    let tags: [String]
    let image: NSImage
    var ratio: CGFloat { image.size.width / max(image.size.height, 1) }
    var filename: String { String(format: "示例_%02d.jpg", id) }
}

@MainActor final class DemoModel: ObservableObject {
    let photos: [SamplePhoto]
    @Published var recent: [Int] = [4, 9, 8]
    @Published var selection = 4
    @Published var section = "全部照片"
    @Published var search = ""
    @Published var filter = "全部"
    @Published var ratings = [4: 5, 7: 4, 9: 4, 6: 5]
    @Published var notes: [Int: String] = [:]
    @Published var viewerControlsHovered = false
    @Published var controlsVisible = false
    @Published var viewing = false
    @Published var inspector = true
    @Published var dark = true
    @Published var size: Double = 230
    @Published var reverse = false
    @Published var showNames = true
    @Published var zoom = false
    init() {
        let items: [(Int, String, String, [String])] = [
            (4,"湖畔午后","山野之间",["湖泊","旅行"]),
            (9,"山谷来信","山野之间",["山野","旅行"]),
            (8,"走进薄雾","森林漫步",["森林","静谧"]),
            (2,"远山与风","山野之间",["山野","旅行"]),
            (1,"公路尽头","在路上",["公路","旅行"]),
            (5,"林间微光","森林漫步",["森林","阳光"]),
            (7,"绿色回响","山野之间",["山野","旅行"]),
            (6,"群星入梦","在路上",["星空","夜晚"]),
            (3,"山间小屋","山野之间",["湖泊","静谧"]),
            (12,"日落以后","在路上",["日落","阳光"]),
            (10,"群山之间","山野之间",["山野","静谧"])
        ]
        photos = items.compactMap { id, title, album, tags in
            guard let url = Bundle.main.url(forResource: String(format: "示例_%02d", id), withExtension: "jpg", subdirectory: "Samples"), let image = NSImage(contentsOf: url) else { return nil }
            return SamplePhoto(id: id, title: title, collection: album, tags: tags, image: image)
        }
    }
    var visible: [SamplePhoto] {
        let result = photos.filter { p in
            let rating = ratings[p.id, default: 0]
            let sectionMatch = section == "全部照片" || (section == "最近浏览" && recent.contains(p.id)) || section == "秋日旅行" || (section == "五星精选" && rating == 5) || (section == "待评分" && rating == 0) || section == p.collection || p.tags.contains(section)
            let choices = Set(filter.components(separatedBy: ","))
            let filterMatch = choices.contains("全部") || (choices.contains("未评分") && rating == 0) || choices.contains("\(rating)星")
            let searchMatch = search.isEmpty || ([p.title, p.filename, p.collection] + p.tags + [notes[p.id, default: ""]]).joined(separator: " ").localizedCaseInsensitiveContains(search)
            return sectionMatch && filterMatch && searchMatch
        }
        let ordered = section == "最近浏览" ? result.sorted { (recent.firstIndex(of:$0.id) ?? 0) < (recent.firstIndex(of:$1.id) ?? 0) } : result
        return reverse ? Array(ordered.reversed()) : ordered
    }
    var current: SamplePhoto? { photos.first { $0.id == selection } }
    func chooseFilter(_ value: String, extending: Bool) {
        guard extending && value != "全部" else { filter = value; return }
        var choices = Set(filter.components(separatedBy:","))
        choices.remove("全部")
        if choices.contains(value) { choices.remove(value) } else { choices.insert(value) }
        filter = choices.isEmpty ? "全部" : choices.sorted().joined(separator:",")
    }
    func filterSelected(_ value: String) -> Bool { filter.components(separatedBy:",").contains(value) }
    func select(_ id: Int) { NSApp.keyWindow?.makeFirstResponder(nil); selection = id }
    func recordVisit() { guard current != nil else { return }; recent.removeAll { $0 == selection }; recent.insert(selection,at:0) }
    func navigate(_ name: String) { NSApp.keyWindow?.makeFirstResponder(nil); section = name; search = ""; filter = "全部"; viewing = false; reconcile() }
    func reconcile() { if !visible.contains(where: { $0.id == selection }) { selection = visible.first?.id ?? -1 }; if visible.isEmpty { viewing = false } }
    func step(_ offset: Int) {
        guard !visible.isEmpty else { return }
        let index = visible.firstIndex(where: { $0.id == selection }) ?? 0
        selection = visible[min(max(index + offset, 0), visible.count - 1)].id
        zoom = false
    }
    func rate(_ value: Int) { guard current != nil else { return }; ratings[selection] = value; reconcile() }
}

struct Palette {
    let dark: Bool
    var canvas: Color { Color(white: dark ? 0.105 : 0.985) }
    var panel: Color { Color(white: dark ? 0.135 : 0.955) }
    var inspector: Color { Color(white: dark ? 0.12 : 0.975) }
    var raised: Color { Color(white: dark ? 0.19 : 0.91) }
    var line: Color { Color.primary.opacity(dark ? 0.085 : 0.08) }
    var muted: Color { Color(white: dark ? 0.60 : 0.43) }
    var accent: Color { dark ? Color(red: 0.43, green: 0.62, blue: 0.94) : Color(red: 0.18, green: 0.39, blue: 0.73) }
}
