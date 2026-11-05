import SwiftUI
import PhotoLibraryCore

/// A small set of personal-photo filters; saved legacy queries remain readable elsewhere.
struct AdvancedFilters: View {
    var sorting = false
    @EnvironmentObject var model: LibraryModel
    @Environment(\.colorScheme) private var scheme
    @State private var opened: String?
    @State private var tagSearch = ""
    @State private var editingRange = false
    @State private var draftFrom = Date()
    @State private var draftTo = Date()
    private var p: DesignPalette { DesignPalette(dark: scheme == .dark) }
    private var allTags: [String] { Set(model.snapshot.tags).union(model.tagFilters).sorted() }
    private var tags: [String] { allTags.filter { tagSearch.isEmpty || $0.localizedStandardContains(tagSearch) } }
    private var tagLabel: String {
        model.tagFilters.isEmpty ? "不限" : model.tagFilters.count == 1 ? model.tagFilters.first! : "\(model.tagFilters.count) 项"
    }
    private var dateLabel: String {
        guard model.dateFilterEnabled else { return "不限" }
        if matchesDate(days: 30) { return "近 30 天" }
        if matchesYear(0) { return "今年" }
        if matchesYear(-1) { return "去年" }
        let formatter = DateFormatter(); formatter.dateFormat = "yy.MM.dd"
        return formatter.string(from: model.dateFrom) + "–" + formatter.string(from: model.dateTo)
    }
    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if sorting {
                        entry("排序依据", value: model.sort.field.rawValue, width: 226, active: false) {
                            VStack(spacing: 1) {
                                ForEach(PhotoSortField.allCases, id: \.self) { field in
                                    choice(field.rawValue, selected: model.sort.field == field) {
                                        if model.sort.field != field { model.sort = .order(field: field, ascending: field == .name) }
                                        opened = nil
                                    }
                                }
                            }.padding(8).frame(width: 224)
                        }
                        entry("排列顺序", value: model.sort.field.directionLabel(ascending: model.sort.ascending), width: 166, active: false) {
                            VStack(spacing: 1) {
                                ForEach([false, true], id: \.self) { ascending in
                                    choice(model.sort.field.directionLabel(ascending: ascending), selected: model.sort.ascending == ascending) {
                                        model.sort = .order(field: model.sort.field, ascending: ascending)
                                        opened = nil
                                    }
                                }
                            }.padding(8).frame(width: 224)
                        }
                    } else {
                    entry("拍摄日期", value: dateLabel, width: 226, active: model.dateFilterEnabled) {
                        datePanel
                    }
                    entry("标签", value: tagLabel, width: 166, active: !model.tagFilters.isEmpty) {
                        tagPanel
                    }
                    }
                }
            }
            Spacer(minLength: 0)
            Button(sorting ? "恢复默认" : "清除") {
                if sorting { model.sort = .dateDescending } else { model.clearAdvancedFilters() }
            }
                .disabled(sorting ? model.sort == .dateDescending : model.advancedFilterCount == 0)
                .help(sorting ? "恢复按拍摄日期从新到旧排序" : "清除筛选，保留搜索和星级")
                .accessibilityLabel(sorting ? "恢复默认排序" : "清除高级条件").padding(.horizontal, 6).frame(height: 28)
            Rectangle().fill(p.line).frame(width: 1, height: 14)
            Button { opened = nil; model.saveSmartAlbum() } label: {
                Image(systemName: "rectangle.stack.badge.plus").frame(width: 28, height: 28)
            }.help("将当前条件保存为智能相册").accessibilityLabel("保存为智能相册")
        }
        .font(.system(size: 12)).foregroundStyle(p.muted).buttonStyle(RowFeedbackStyle())
        .padding(.horizontal, 20).frame(height: 42).background(p.canvas)
        .overlay(alignment: .bottom) { Rectangle().fill(p.line).frame(height: 1) }
        .onChange(of: opened) { _, value in model.filterPopoverPresented = value != nil }
        .onDisappear { model.filterPopoverPresented = false }
    }
    private func entry<Content: View>(_ title: String, value: String, width: CGFloat, active: Bool, @ViewBuilder content: @escaping () -> Content) -> some View {
        Button {
            editingRange = false; tagSearch = ""; opened = title
        } label: {
            HStack(spacing: 7) {
                Text(title).foregroundStyle(p.muted)
                Text(value).foregroundStyle(active || sorting ? Color.primary : p.muted.opacity(0.65))
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .medium)).foregroundStyle(p.muted)
            }.font(.system(size: 12)).padding(.horizontal, 9).frame(width: width, height: 28)
                .background(Color.primary.opacity(opened == title ? 0.055 : active ? 0.03 : 0), in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }.buttonStyle(RowFeedbackStyle())
            .accessibilityLabel(sorting ? title : "筛选" + title).accessibilityValue(value)
            .help(sorting ? title + "：" + value : title == "标签" ? model.tagFilters.sorted().joined(separator: "、") : model.dateFilterEnabled ? model.dateFilterLabel : "按拍摄日期筛选；未记录时使用文件修改日期")
            .popover(isPresented: Binding(get: { opened == title }, set: { if !$0 && opened == title { opened = nil } }), arrowEdge: .bottom) {
                content().foregroundStyle(Color.primary).tint(p.accent)
                    .background(p.panel).preferredColorScheme(scheme)
            }
    }
    private var tagPanel: some View {
        VStack(spacing: 6) {
            HStack {
                Text("可多选").foregroundStyle(p.muted)
                Spacer()
                Button("清除") { model.tagFilters = [] }.disabled(model.tagFilters.isEmpty)
                    .foregroundStyle(p.muted).buttonStyle(RowFeedbackStyle()).help("清除标签筛选")
            }.font(.system(size: 11)).padding(.horizontal, 6).padding(.top, 3)
            if allTags.count > 6 {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(p.muted)
                    TextField("查找标签", text: $tagSearch).textFieldStyle(.plain)
                }.font(.system(size: 12)).padding(.horizontal, 8).frame(height: 29)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 5))
            }
            ScrollView {
                VStack(spacing: 1) {
                    if tags.isEmpty {
                        Text(tagSearch.isEmpty ? "还没有标签" : "没有匹配的标签")
                            .font(.system(size: 12)).foregroundStyle(p.muted).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    ForEach(tags, id: \.self) { tag in
                        choice(tag, selected: model.tagFilters.contains(tag)) {
                            if model.tagFilters.contains(tag) { model.tagFilters.remove(tag) }
                            else { model.tagFilters.insert(tag) }
                        }
                    }
                }
            }.frame(maxHeight: 260).fixedSize(horizontal: false, vertical: true)
        }.padding(8).frame(width: 224)
            .help("多个标签匹配任意一个；与日期、星级条件同时满足")
    }
    private var datePanel: some View {
        VStack(spacing: 0) {
            if editingRange {
                HStack(spacing: 5) {
                    Button { editingRange = false } label: {
                        Image(systemName: "chevron.left").font(.system(size: 11)).frame(width: 26, height: 28)
                    }.buttonStyle(RowFeedbackStyle()).help("返回日期选项").accessibilityLabel("返回日期选项")
                    Text("自定义范围").font(.system(size: 12))
                    Spacer()
                }.padding(.bottom, 8)
                FilterDateRangeEditor(from: draftFrom, to: draftTo, palette: p) { start, end in
                    draftFrom = start; draftTo = end
                }
                divider.padding(.top, 10).padding(.bottom, 8)
                HStack {
                    Button("取消") { opened = nil }.buttonStyle(RowFeedbackStyle()).foregroundStyle(p.muted)
                        .frame(height: 28)
                    Spacer()
                    Button {
                        model.setDateRange(from: draftFrom, to: draftTo); opened = nil
                    } label: {
                        Text("应用范围").foregroundStyle(.white).padding(.horizontal, 13).frame(height: 28)
                            .background(p.accent, in: RoundedRectangle(cornerRadius: 5))
                    }.buttonStyle(RowFeedbackStyle()).keyboardShortcut(.return, modifiers: [])
                }.font(.system(size: 12)).padding(.horizontal, 4)
            } else {
                VStack(spacing: 1) {
                    choice("不限时间", selected: !model.dateFilterEnabled) { model.dateFilterEnabled = false; opened = nil }
                    divider.padding(.vertical, 5)
                    choice("近 30 天", selected: matchesDate(days: 30)) {
                        model.setDateRange(from: Calendar.current.date(byAdding: .day, value: -29, to: Date())!, to: Date()); opened = nil
                    }
                    choice("今年", selected: matchesYear(0)) { selectYear(0) }
                    choice("去年", selected: matchesYear(-1)) { selectYear(-1) }
                    divider.padding(.vertical, 5)
                    choice("自定义范围…", selected: false, disclosure: true) {
                        draftFrom = model.dateFrom; draftTo = model.dateTo; editingRange = true
                    }
                }
            }
        }.padding(8).frame(width: editingRange ? 264 : 224)
    }
    private var divider: some View { Rectangle().fill(p.line).frame(height: 1).padding(.horizontal, 6) }
    private func yearRange(_ offset: Int) -> DateInterval {
        Calendar.current.dateInterval(of: .year, for: Calendar.current.date(byAdding: .year, value: offset, to: Date())!)!
    }
    private func matchesYear(_ offset: Int) -> Bool {
        let range = yearRange(offset)
        return model.dateFilterEnabled && Calendar.current.isDate(model.dateFrom, inSameDayAs: range.start)
            && Calendar.current.isDate(model.dateTo, inSameDayAs: range.end.addingTimeInterval(-1))
    }
    private func selectYear(_ offset: Int) {
        let range = yearRange(offset); model.setDateRange(from: range.start, to: range.end.addingTimeInterval(-1)); opened = nil
    }
    private func matchesDate(days: Int) -> Bool {
        model.dateFilterEnabled && Calendar.current.isDateInToday(model.dateTo) && Calendar.current.isDate(model.dateFrom, inSameDayAs: Calendar.current.date(byAdding: .day, value: -(days - 1), to: Date())!)
    }
    private func choice(_ title: String, selected: Bool, disclosure: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Image(systemName: disclosure ? "chevron.right" : "checkmark")
                    .font(.system(size: disclosure ? 9 : 10, weight: .medium))
                    .foregroundStyle(disclosure ? p.muted : p.accent).frame(width: 12).opacity(disclosure || selected ? 1 : 0)
            }.font(.system(size: 12)).padding(.horizontal, 8).frame(height: 29)
                .foregroundStyle(Color.primary.opacity(0.9)).contentShape(Rectangle())
        }.buttonStyle(RowFeedbackStyle()).accessibilityAddTraits(selected ? .isSelected : []).help(title)
    }
}

/// Compact range calendar avoids the platform's mismatched segmented date fields.
private struct FilterDateRangeEditor: View {
    let from: Date
    let to: Date
    let palette: DesignPalette
    let onChange: (Date, Date) -> Void
    @State private var editingEnd = false
    @State private var month: Date
    private let calendar = Calendar.current

    init(from: Date, to: Date, palette: DesignPalette, onChange: @escaping (Date, Date) -> Void) {
        self.from = from; self.to = to; self.palette = palette; self.onChange = onChange
        _month = State(initialValue: Calendar.current.dateInterval(of: .month, for: from)!.start)
    }
    private var year: Int { calendar.component(.year, from: month) }
    private var monthNumber: Int { calendar.component(.month, from: month) }
    private var first: Date { calendar.dateInterval(of: .month, for: month)!.start }
    private var offset: Int { (calendar.component(.weekday, from: first) + 5) % 7 }
    private var dayCount: Int { calendar.range(of: .day, in: .month, for: month)!.count }
    private var years: [Int] {
        Array(min(1900, calendar.component(.year, from: from))...max(calendar.component(.year, from: Date()) + 1, calendar.component(.year, from: to)))
    }
    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 2) {
                endpoint("开始", date: from, end: false)
                endpoint("结束", date: to, end: true)
            }
            HStack(spacing: 2) {
                monthArrow("chevron.left", offset: -1)
                Spacer(minLength: 0)
                Menu {
                    ForEach(years.reversed(), id: \.self) { value in Button("\(String(value)) 年") { setMonth(year: value, month: monthNumber) } }
                } label: { Text("\(String(year)) 年").font(.system(size: 12)) }
                Menu {
                    ForEach(1...12, id: \.self) { value in Button("\(value) 月") { setMonth(year: year, month: value) } }
                } label: { Text("\(monthNumber) 月").font(.system(size: 12)) }
                Spacer(minLength: 0)
                monthArrow("chevron.right", offset: 1)
            }.menuStyle(.borderlessButton).tint(Color.primary).fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 3) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { day in
                    Text(day).font(.system(size: 10)).foregroundStyle(palette.muted).frame(height: 18)
                }
                ForEach(0..<(offset + dayCount), id: \.self) { index in
                    if index < offset { Color.clear.frame(height: 26) }
                    else { dayButton(index - offset + 1) }
                }
            }
        }
    }
    private func endpoint(_ title: String, date: Date, end: Bool) -> some View {
        Button {
            editingEnd = end
            month = calendar.dateInterval(of: .month, for: date)!.start
        } label: {
            HStack {
                Text(title).foregroundStyle(palette.muted)
                Spacer()
                Text(date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))).monospacedDigit()
            }.font(.system(size: 12)).padding(.horizontal, 8).frame(height: 30)
                .background(editingEnd == end ? Color.primary.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 5))
                .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(editingEnd == end ? palette.line : .clear) }
                .contentShape(Rectangle())
        }.buttonStyle(RowFeedbackStyle()).accessibilityLabel(title + "日期").accessibilityValue(date.formatted(date: .numeric, time: .omitted))
    }
    private func dayButton(_ day: Int) -> some View {
        let date = calendar.date(byAdding: .day, value: day - 1, to: first)!
        let boundary = calendar.isDate(date, inSameDayAs: from) || calendar.isDate(date, inSameDayAs: to)
        let inside = date >= calendar.startOfDay(for: from) && date <= calendar.startOfDay(for: to)
        return Button {
            if editingEnd { onChange(min(from, date), date) }
            else { onChange(date, max(date, to)); editingEnd = true }
        } label: {
            Text(String(day)).font(.system(size: 11)).monospacedDigit().frame(maxWidth: .infinity).frame(height: 26)
                .foregroundStyle(boundary ? Color.white : Color.primary.opacity(0.85))
                .background {
                    ZStack {
                        if inside {
                            HStack(spacing: 0) {
                                Rectangle().fill(calendar.isDate(date, inSameDayAs: from) ? .clear : palette.accent.opacity(0.10))
                                Rectangle().fill(calendar.isDate(date, inSameDayAs: to) ? .clear : palette.accent.opacity(0.10))
                            }
                        }
                        if boundary { RoundedRectangle(cornerRadius: 5).fill(palette.accent).frame(width: 28) }
                    }
                }
                .contentShape(Rectangle())
        }.buttonStyle(RowFeedbackStyle()).accessibilityLabel(date.formatted(date: .complete, time: .omitted))
    }
    private func monthArrow(_ symbol: String, offset: Int) -> some View {
        Button { month = calendar.date(byAdding: .month, value: offset, to: first)! } label: {
            Image(systemName: symbol).font(.system(size: 10)).frame(width: 24, height: 24).contentShape(Rectangle())
        }.buttonStyle(RowFeedbackStyle()).accessibilityLabel(offset < 0 ? "上个月" : "下个月")
    }
    private func setMonth(year: Int, month: Int) {
        self.month = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
    }
}
