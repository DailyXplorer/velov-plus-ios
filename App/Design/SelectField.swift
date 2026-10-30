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

    private var selected: SelectOption<Value>? { options.first { $0.value == value } ?? options.first }
    private var inline: Bool { layout == .inline }

    var body: some View {
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

    @ViewBuilder
    private var title: some View {
        if !hideLabel { Text(label).typo(.caps(13)).foregroundStyle(Palette.inkSoft).fixedSize() }
    }

    private var trigger: some View {
        Menu {
            Picker(label, selection: $value) {
                ForEach(options) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: inline ? 8 : 12) {
                shown.frame(maxWidth: layout == .stacked ? .infinity : nil, alignment: .leading)
                Icon(.arrowRight, .bold, size: 13).foregroundStyle(Palette.ink)
                    .rotationEffect(.degrees(90))
                    .frame(width: 28, height: 28).background(Circle().fill(Palette.mist))
            }
            .padding(.leading, inline ? 10 : 18).padding(.trailing, inline ? 0 : 7)
            .frame(height: 42)
            .background { if !inline { Capsule().fill(Palette.white) } }
            .overlay { if !inline { Capsule().strokeBorder(Palette.inkLine, lineWidth: 1) } }
            .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        .buttonStyle(.plain)
        .tint(Palette.red)
        .accessibilityLabel("\(label), \(selected?.label ?? "")")
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
}
