import SwiftUI

struct SelectOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var short: String?
    var id: Value { value }
}

struct SelectField<Value: Hashable>: View {
    enum Layout { case row, stacked, inline }

    let label: String
    var hideLabel = false
    @Binding var value: Value
    let options: [SelectOption<Value>]
    var layout = Layout.row
    @State private var open = false
    @State private var width: CGFloat = 0

    private var selected: SelectOption<Value>? { options.first { $0.value == value } ?? options.first }
    private var inline: Bool { layout == .inline }

    var body: some View {
        Group {
            switch layout {
            case .row: HStack(spacing: 12) { title; trigger }
            case .stacked: VStack(alignment: .leading, spacing: 6) { title; trigger }
            case .inline:
                HStack(spacing: 0) {
                    Rectangle().fill(Palette.inkLine).frame(width: 1, height: 22).padding(.leading, 8)
                    trigger
                }
            }
        }
        .zIndex(open ? 100 : 0)
    }

    @ViewBuilder
    private var title: some View {
        if !hideLabel { Text(label).typo(.caps(13)).foregroundStyle(Palette.inkSoft).fixedSize() }
    }

    private var trigger: some View {
        Button { withAnimation(.easeOut(duration: 0.16)) { open.toggle() } } label: {
            HStack(spacing: inline ? 8 : 12) {
                shown.frame(maxWidth: layout == .stacked ? .infinity : nil, alignment: .leading)
                Icon(.arrowRight, .bold, size: 13).foregroundStyle(Palette.ink)
                    .rotationEffect(.degrees(open ? -90 : 90))
                    .frame(width: 28, height: 28).background(Circle().fill(Palette.mist))
            }
            .padding(.leading, inline ? 10 : 18).padding(.trailing, inline ? 0 : 7)
            .frame(height: 42)
            .background { if !inline { Capsule().fill(Palette.white) } }
            .overlay { if !inline { Capsule().strokeBorder(Palette.inkLine, lineWidth: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(selected?.label ?? "")")
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .overlay(alignment: inline ? .topTrailing : .topLeading) {
            if open {
                list.offset(x: inline ? 7 : 0, y: 50).transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
    }

    @ViewBuilder
    private var shown: some View {
        if inline {
            Text(selected?.short ?? selected?.label ?? "").typo(.body(14)).foregroundStyle(Palette.ink).lineLimit(1)
        } else {
            ZStack(alignment: .leading) {
                ForEach(options) { Text($0.label).lineLimit(1).hidden() }
                Text(selected?.label ?? "").foregroundStyle(Palette.ink).lineLimit(1)
            }
            .typo(.body(15))
        }
    }

    private var list: some View {
        Group {
            if options.count > 8 { ScrollView { rows }.scrollIndicators(.visible).frame(height: 336) } else { rows }
        }
        .padding(6)
        .frame(width: inline ? 220 : max(width, 200))
        .ringed(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(options) { option in
                let chosen = option.value == value
                Button {
                    value = option.value
                    withAnimation(.easeOut(duration: 0.16)) { open = false }
                } label: {
                    Text(option.label).typo(.body(14)).lineLimit(1)
                        .foregroundStyle(chosen ? Palette.red : Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .padding(.horizontal, 12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(chosen ? Palette.mist : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }
}
