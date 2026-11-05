import SwiftUI
import AppKit

struct DemoRoot: View {
    @EnvironmentObject var m: DemoModel
    @State private var searchFocused = false
    @State private var searchHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var p: Palette { Palette(dark: m.dark) }
    var body: some View {
        Group {
        if m.viewing { ImmersiveViewer() } else {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar.frame(width: 196)
                Rectangle().fill(p.line).frame(width: 1)
                VStack(spacing: 0) {
                    toolbar
                    Rectangle().fill(p.line).frame(height: 1)
                    HStack(spacing: 0) {
                        gallery
                        if m.inspector {
                            Rectangle().fill(p.line).frame(width: 1)
                            DemoInspector().frame(width: 264)
                        }
                    }
                }
            }
            Rectangle().fill(p.line).frame(height: 1)
            footer
        }
        }
        }
        .background(p.canvas).foregroundStyle(Color.primary)
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(m.dark ? .dark : .light)
        .onChange(of: m.dark) { _, dark in NSApp.keyWindow?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua) }
        .onChange(of: m.viewing) { _, viewing in if viewing { m.recordVisit() }; (NSApp.delegate as? DemoDelegate)?.setImmersive(viewing) }
        .onChange(of: m.selection) { _, _ in if m.viewing && m.section != "最近浏览" { m.recordVisit() } }
        .onChange(of: m.search) { _, _ in m.reconcile() }
        .onChange(of: m.filter) { _, _ in m.reconcile() }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 16,weight: .medium)).foregroundStyle(p.accent)
                Text("拾光").font(.system(size: 14,weight: .semibold))
                Spacer()
                Text("DEMO").font(.system(size: 9,weight: .medium,design: .rounded)).tracking(0.8).foregroundStyle(p.muted.opacity(0.8))
            }.padding(.horizontal,20).padding(.top,36).padding(.bottom,16)
            sectionLabel("照片库")
            nav("全部照片", "square.grid.2x2", count: m.photos.count)
            nav("最近浏览", "clock")
            nav("五星精选", "star", count: m.photos.filter { m.ratings[$0.id] == 5 }.count)
            nav("待评分", "circle.dashed", count: m.photos.filter { m.ratings[$0.id, default:0] == 0 }.count)
            sectionLabel("相册", top:16)
            nav("山野之间", "rectangle.stack")
            nav("森林漫步", "rectangle.stack")
            nav("在路上", "rectangle.stack")
            sectionLabel("文件夹", top:16)
            nav("秋日旅行", "folder")
            sectionLabel("标签", top:16)
            HStack(spacing:7) {
                ForEach(["旅行","山野","森林"], id: \.self) { tag in
                    Button { m.navigate(tag) } label: { Text(tag).font(.system(size:11)).padding(.horizontal,9).padding(.vertical,5).background(m.section == tag ? p.accent.opacity(0.25) : p.raised.opacity(0.65),in:RoundedRectangle(cornerRadius:5)) }.buttonStyle(RowFeedbackStyle())
                }
            }.padding(.horizontal,20)
            Spacer(minLength: 20)
            HStack(spacing:8) { Image(systemName:"internaldrive"); Text("示例照片库"); Spacer(); Circle().fill(Color.green.opacity(0.7)).frame(width:5,height:5) }.font(.system(size:11)).foregroundStyle(p.muted).padding(20)
        }.frame(maxHeight:.infinity).background(p.panel)
    }
    func sectionLabel(_ title: String, top: CGFloat = 0) -> some View {
        Text(title).font(.system(size:11,weight:.medium)).foregroundStyle(p.muted).padding(.horizontal,20).padding(.top,top).padding(.bottom,9)
    }
    func nav(_ name: String, _ icon: String, count: Int? = nil) -> some View {
        Button { m.navigate(name) } label: {
            HStack(spacing:10) {
                Image(systemName:icon).font(.system(size:13,weight:.regular)).frame(width:18).foregroundStyle(m.section == name ? p.accent : p.muted)
                Text(name).font(.system(size:13,weight:m.section == name ? .medium : .regular))
                Spacer()
                if let count { Text("\(count)").font(.system(size:10,design:.rounded)).foregroundStyle(p.muted) }
            }.padding(.horizontal,10).frame(height:32).background(m.section == name ? p.accent.opacity(m.dark ? 0.14 : 0.12) : .clear,in:RoundedRectangle(cornerRadius:5))
        }.buttonStyle(RowFeedbackStyle()).accessibilityAddTraits(m.section == name ? .isSelected : []).padding(.horizontal,10).padding(.bottom,2)
    }
    var toolbar: some View {
        HStack(spacing:12) {
            HStack(spacing:8) {
                Text(m.section).font(.system(size:13,weight:.semibold)).lineLimit(1)
                Text("\(m.visible.count)").font(.system(size:11,weight:.medium,design:.rounded)).monospacedDigit().foregroundStyle(p.muted).frame(width:26,alignment:.leading)
            }.fixedSize()
            HStack(spacing:2) {
                ForEach(["全部","未评分","1星","2星","3星","4星","5星"],id: \.self) { value in
                    Button {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        m.chooseFilter(value, extending:(NSApp.currentEvent?.modifierFlags.contains(.command) == true || NSEvent.modifierFlags.contains(.command)))
                    } label: {
                        Text(value).font(.system(size:11,weight:m.filterSelected(value) ? .semibold : .medium))
                            .frame(width:value == "未评分" ? 46 : 32,height:26)
                            .foregroundStyle(m.filterSelected(value) ? p.accent : p.muted)
                            .background(m.filterSelected(value) ? p.accent.opacity(m.dark ? 0.16 : 0.10) : .clear,in:RoundedRectangle(cornerRadius:5))
                    }.buttonStyle(RowFeedbackStyle())
                        .help("\(value) · 按住 ⌘ 点击可多选")
                        .accessibilityAddTraits(m.filterSelected(value) ? .isSelected : [])
                }
            }.padding(3).background(p.panel.opacity(0.65),in:RoundedRectangle(cornerRadius:8))
                .overlay { RoundedRectangle(cornerRadius:8).strokeBorder(p.line.opacity(0.6),lineWidth:1) }
            Spacer(minLength:8)
            HStack(spacing:6) {
                Image(systemName:"magnifyingglass").font(.system(size:12)).foregroundStyle(searchFocused || searchHovered ? p.accent : p.muted)
                StableSearchField(text:$m.search,focused:$searchFocused,hovered:$searchHovered).frame(height:16)
                Button { m.search = ""; focusSearch() } label: {
                    Image(systemName:"xmark.circle.fill").font(.system(size:11)).foregroundStyle(p.muted).frame(width:14,height:20)
                }.buttonStyle(.plain).opacity(m.search.isEmpty ? 0 : 1).disabled(m.search.isEmpty).accessibilityHidden(m.search.isEmpty).accessibilityLabel("清除搜索")
            }.padding(.horizontal,9).frame(width:184,height:30)
                .background(p.raised.opacity(searchFocused ? 0.65 : searchHovered ? 0.46 : 0.27),in:RoundedRectangle(cornerRadius:7))
                .overlay { RoundedRectangle(cornerRadius:7).strokeBorder(searchFocused ? p.accent.opacity(0.8) : searchHovered ? p.accent.opacity(0.4) : p.line,lineWidth:1) }
                .shadow(color:p.accent.opacity(searchFocused ? 0.09 : searchHovered ? 0.04 : 0),radius:3)
                .contentShape(Rectangle()).onTapGesture { focusSearch() }.onHover { searchHovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration:0.18),value:searchFocused)
                .animation(reduceMotion ? nil : .easeOut(duration:0.15),value:searchHovered)
                .help("搜索照片、标签 · ⌘F")
            Rectangle().fill(p.line).frame(width:1,height:18)
            Menu {
                Button(m.reverse ? "按默认顺序" : "倒序排列") { m.reverse.toggle() }
                Toggle("显示照片名称",isOn:$m.showNames)
            } label: { Image(systemName:"arrow.up.arrow.down").font(.system(size:13)).foregroundStyle(p.muted).frame(width:20,height:28) }.menuStyle(.borderlessButton).fixedSize().help("排列与显示")
            iconButton(m.dark ? "sun.max" : "moon", "切换深浅色") { m.dark.toggle() }
            iconButton("sidebar.right", "显示或隐藏信息") { m.inspector.toggle() }
        }.padding(.horizontal,20).padding(.top,28).frame(height:72).background(p.canvas)
    }
    func focusSearch() { NotificationCenter.default.post(name:Notification.Name("PhotoShelfFocusSearch"),object:nil) }
    var gallery: some View {
        VStack(alignment:.leading,spacing:0) {
            if m.visible.isEmpty {
                VStack(spacing:14) {
                    Image(systemName:"magnifyingglass").font(.system(size:26,weight:.light)).frame(width:64,height:64).background(p.raised.opacity(0.35),in:Circle())
                    Text("没有匹配的照片").font(.system(size:15,weight:.medium)).foregroundStyle(Color.primary)
                    Text(m.search.isEmpty ? "试试其他星级，或清除筛选条件。" : "换个关键词，或清除搜索和星级筛选。").font(.system(size:12))
                    Button("清除筛选条件") { m.search = ""; m.filter = "全部"; m.reconcile() }
                        .buttonStyle(.plain).font(.system(size:12,weight:.medium)).foregroundStyle(p.accent).padding(.horizontal,14).padding(.vertical,8)
                        .background(p.accent.opacity(0.10),in:RoundedRectangle(cornerRadius:6))
                }.foregroundStyle(p.muted).frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                GeometryReader { geo in
                    let columns = max(2, Int((geo.size.width - 32) / CGFloat(m.size)))
                    ScrollViewReader { proxy in
                        ScrollView {
                            MasonryLayout(columns:columns,spacing:12) {
                                ForEach(m.visible) { photo in DemoPhotoTile(photo:photo).id(photo.id) }
                            }.padding(16)
                        }.onChange(of:m.selection) { _, id in withAnimation(reduceMotion ? nil : .easeOut(duration:0.18)) { proxy.scrollTo(id) } }
                        .onAppear { if m.selection != m.visible.first?.id { proxy.scrollTo(m.selection,anchor:.center) } }
                    }
                }
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity).background(p.canvas)
    }
    var footer: some View {
        HStack(spacing:8) {
            Image(systemName:"circle.inset.filled").font(.system(size:6)).foregroundStyle(p.accent)
            Text("示例图库 · 修改不保存").font(.system(size:11)).foregroundStyle(p.muted)
            Spacer()
            Text(m.viewing ? "← → 切换    0–5 评分    Esc 返回" : "双击或空格查看大图    ·    0–5 评分").font(.system(size:10)).foregroundStyle(p.muted)
            Spacer()
            Image(systemName:"square.grid.3x3").font(.system(size:10)).foregroundStyle(p.muted)
            Slider(value:$m.size,in:180...320).controlSize(.mini).frame(width:90).accessibilityLabel("照片大小").disabled(m.viewing)
            Image(systemName:"square.grid.2x2").font(.system(size:10)).foregroundStyle(p.muted)
        }.padding(.horizontal,18).frame(height:32).background(p.panel)
    }
    func iconButton(_ icon: String,_ label:String,action:@escaping()->Void) -> some View {
        Button(action:action) { Image(systemName:icon).font(.system(size:13,weight:.regular)).foregroundStyle(p.muted).frame(width:22,height:26).contentShape(Rectangle()) }.buttonStyle(QuietToolbarStyle()).help(label).accessibilityLabel(label)
    }
}

struct MasonryLayout: Layout {
    var columns: Int
    var spacing: CGFloat
    func positions(_ width: CGFloat, _ views: Subviews) -> (CGSize,[CGPoint]) {
        let w = (width - CGFloat(columns-1)*spacing)/CGFloat(columns)
        var heights = Array(repeating:CGFloat.zero,count:columns)
        var points: [CGPoint] = []
        for view in views {
            let column = heights.indices.min(by:{ heights[$0] < heights[$1] }) ?? 0
            points.append(CGPoint(x:CGFloat(column)*(w+spacing),y:heights[column]))
            heights[column] += view.sizeThatFits(ProposedViewSize(width:w,height:nil)).height + spacing
        }
        return (CGSize(width:width,height:max(0,(heights.max() ?? 0)-spacing)),points)
    }
    func sizeThatFits(proposal:ProposedViewSize, subviews:Subviews,cache:inout()) -> CGSize { positions(proposal.width ?? 800,subviews).0 }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout()) {
        let result = positions(bounds.width,subviews)
        let w = (bounds.width-CGFloat(columns-1)*spacing)/CGFloat(columns)
        for (index,view) in subviews.enumerated() { view.place(at:CGPoint(x:bounds.minX+result.1[index].x,y:bounds.minY+result.1[index].y),anchor:.topLeading,proposal:ProposedViewSize(width:w,height:nil)) }
    }
}

struct DemoPhotoTile: View {
    @EnvironmentObject var m: DemoModel
    let photo: SamplePhoto
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var p: Palette { Palette(dark:m.dark) }
    var selected: Bool { m.selection == photo.id }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Image(nsImage:photo.image).resizable().aspectRatio(photo.ratio,contentMode:.fit)
                .clipShape(RoundedRectangle(cornerRadius:4))
                .overlay(alignment:.bottomTrailing) {
                    if m.ratings[photo.id,default:0] > 0 { HStack(spacing:3) { Image(systemName:"star.fill").font(.system(size:8)); Text("\(m.ratings[photo.id,default:0])").font(.system(size:11,weight:.medium)) }.foregroundStyle(.white).padding(.horizontal,7).padding(.vertical,4).background(.black.opacity(0.48),in:Capsule()).padding(8) }
                }
                .overlay { RoundedRectangle(cornerRadius:4).strokeBorder(selected ? p.accent : Color.white.opacity(hover ? 0.35 : 0.04),lineWidth:selected ? 1.5 : 1) }
            if m.showNames {
                HStack(spacing:4) { Text(photo.title).lineLimit(1).font(.system(size:12,weight:selected ? .medium : .regular)).foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.78)); Spacer();  }.padding(.horizontal,1)
            }
        }.padding(.bottom,6).background(selected ? p.accent.opacity(0.10) : hover ? Color.primary.opacity(0.045) : .clear,in:RoundedRectangle(cornerRadius:5)).animation(reduceMotion ? nil : .easeOut(duration:0.14),value:hover).contentShape(Rectangle()).onHover { hover = $0 }
            .onTapGesture(count:2) { m.select(photo.id); m.viewing = true; m.zoom = false }
            .onTapGesture { m.select(photo.id) }
            .accessibilityElement(children:.ignore).accessibilityLabel(photo.title).accessibilityValue("\(m.ratings[photo.id,default:0]) 星").accessibilityAddTraits(selected ? [.isButton,.isSelected] : .isButton)
            .accessibilityAction { m.select(photo.id) }
            .contextMenu { Button("查看大图") { m.select(photo.id); m.viewing = true }; Menu("评分") { ForEach(0...5,id:\.self) { rating in Button(rating == 0 ? "清除评分" : "\(rating) 星") { m.select(photo.id); m.rate(rating) } } } }
    }
}

struct QuietToolbarStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { FeedbackBody(label:configuration.label,pressed:configuration.isPressed,padding:3) }
}
struct RowFeedbackStyle: ButtonStyle {
    func makeBody(configuration:Configuration)->some View { FeedbackBody(label:configuration.label,pressed:configuration.isPressed,padding:0) }
}
private struct FeedbackBody<Label: View>: View {
    let label: Label
    let pressed: Bool
    let padding: CGFloat
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false
    var body: some View {
        label.padding(padding).contentShape(RoundedRectangle(cornerRadius:5))
            .background(Color.primary.opacity(enabled ? (pressed ? 0.10 : hover ? 0.055 : 0) : 0),in:RoundedRectangle(cornerRadius:5))
            .opacity(enabled ? 1 : 0.3).onHover { hover = $0 && enabled }
            .animation(reduceMotion ? nil : .easeOut(duration:0.12),value:hover)
    }
}
