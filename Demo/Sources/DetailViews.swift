import SwiftUI

struct RatingControl: View {
    @EnvironmentObject var m: DemoModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = 0
    private var rating: Int { m.ratings[m.selection,default:0] }
    var body: some View {
        HStack(spacing:3) {
            ForEach(1...5,id:\.self) { value in
                Button { m.rate(rating == value ? 0 : value) } label: {
                    Image(systemName:value <= (hover > 0 ? hover : rating) ? "star.fill" : "star")
                        .font(.system(size:13,weight:.regular))
                        .foregroundStyle(value <= (hover > 0 ? hover : rating) ? Color(red:0.85,green:0.68,blue:0.38) : Palette(dark:colorScheme == .dark).muted.opacity(0.8))
                        .frame(width:24,height:30).contentShape(Rectangle())
                }.buttonStyle(.plain).onHover { hover = $0 ? value : 0 }
                    .accessibilityLabel(rating == value ? "清除评分" : "评为 \(value) 星")
                    .accessibilityValue("当前 \(rating) 星")
                    .help(rating == value ? "再次点击清除评分 · 0" : "评为 \(value) 星 · \(value)")
            }
        }.animation(reduceMotion ? nil : .easeOut(duration:0.12),value:hover)
            .onChange(of:m.selection) { _,_ in hover = 0 }
    }
}
struct DemoInspector: View {
    @EnvironmentObject var m: DemoModel
    @FocusState private var editingNote: Bool
    var p: Palette { Palette(dark:m.dark) }
    var body: some View {
        ScrollView {
            if let photo = m.current {
                VStack(alignment:.leading,spacing:0) {
                    HStack {
                        Text("照片信息").font(.system(size:12,weight:.semibold))
                        Spacer()
                        Text("JPEG").font(.system(size:10,weight:.medium,design:.rounded)).foregroundStyle(p.muted)
                            .padding(.horizontal,6).padding(.vertical,3).background(p.raised.opacity(0.5),in:RoundedRectangle(cornerRadius:4))
                    }.padding(.bottom,14)
                    Image(nsImage:photo.image).resizable().aspectRatio(contentMode:.fit)
                        .frame(maxWidth:.infinity).frame(height:132)
                        .background(p.canvas,in:RoundedRectangle(cornerRadius:6))
                        .clipShape(RoundedRectangle(cornerRadius:6))
                        .overlay { RoundedRectangle(cornerRadius:6).strokeBorder(p.line,lineWidth:1) }
                        .accessibilityHidden(true)
                    Text(photo.title).font(.system(size:16,weight:.semibold)).lineLimit(2).padding(.top,16)
                    Text(photo.filename).font(.system(size:11)).foregroundStyle(p.muted).padding(.top,5).textSelection(.enabled)
                    HStack {
                        Text("评分").font(.system(size:12)).foregroundStyle(p.muted)
                        Spacer()
                        RatingControl()
                    }.padding(.top,10)
                    divider
                    label("标签")
                    HStack(spacing:6) {
                        ForEach(photo.tags,id:\.self) { tag in
                            Button { m.navigate(tag) } label: {
                                Text(tag).font(.system(size:11)).padding(.horizontal,10).padding(.vertical,6)
                                    .foregroundStyle(Color.primary.opacity(0.8)).background(p.raised.opacity(0.55),in:RoundedRectangle(cornerRadius:5))
                            }.buttonStyle(RowFeedbackStyle()).help("查看带有“\(tag)”的照片")
                        }
                    }.padding(.top,9)
                    divider
                    label("备注")
                    TextField("记下这个瞬间…",text:Binding(get:{ m.notes[photo.id,default:""] },set:{ m.notes[photo.id] = $0 }),axis:.vertical)
                        .textFieldStyle(.plain).font(.system(size:12)).lineSpacing(4).lineLimit(3...5)
                        .focused($editingNote).padding(10)
                        .background(p.canvas.opacity(0.65),in:RoundedRectangle(cornerRadius:6))
                        .overlay { RoundedRectangle(cornerRadius:6).strokeBorder(editingNote ? p.accent.opacity(0.65) : p.line,lineWidth:1) }
                        .padding(.top,9).accessibilityLabel("照片备注")
                    divider
                    label("文件信息")
                    VStack(spacing:12) {
                        row("尺寸", "\(Int(photo.image.size.width)) × \(Int(photo.image.size.height))")
                        row("格式", "JPEG")
                        row("所在相册", photo.collection)
                    }.padding(.top,14)
                    HStack(alignment:.top,spacing:7) {
                        Image(systemName:"folder").font(.system(size:11))
                        Text("示例照片 / 秋日旅行").lineLimit(2)
                    }.font(.system(size:11)).foregroundStyle(p.muted).padding(.top,22)
                }.padding(18)
            } else {
                VStack(spacing:12) {
                    Image(systemName:"photo").font(.system(size:24,weight:.light))
                    Text("选择照片以查看详情").font(.system(size:12))
                }.foregroundStyle(p.muted).frame(maxWidth:.infinity).padding(.top,72)
            }
        }.frame(maxHeight:.infinity).background(p.inspector)
    }
    var divider: some View { Rectangle().fill(p.line).frame(height:1).padding(.vertical,16) }
    func label(_ title:String)->some View { Text(title).font(.system(size:11,weight:.semibold)).foregroundStyle(p.muted) }
    func row(_ label:String,_ value:String)->some View {
        HStack(alignment:.firstTextBaseline,spacing:12) {
            Text(label).foregroundStyle(p.muted)
            Spacer(minLength:4)
            Text(value).lineLimit(2).multilineTextAlignment(.trailing).textSelection(.enabled)
        }.font(.system(size:12))
    }
}
