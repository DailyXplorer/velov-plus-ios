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
    @State private var choosing = false

    private var selected: SelectOption<Value>? { options.first { $0.value == value } ?? options.first }
    private var inline: Bool { layout == .inline }
    private var inForm: Bool { !hideLabel || layout == .stacked }

    var body: some View {
        switch layout {
        case .row: HStack(spacing: 12) { title; trigger }.onChange(of: value) { Haptics.selection() }
        case .stacked: VStack(alignment: .leading, spacing: 6) { title; trigger }.onChange(of: value) { Haptics.selection() }
        case .inline:
            HStack(spacing: 0) {
                Rectangle().fill(Palette.inkLine).frame(width: 1, height: 22).padding(.leading, 8)
                trigger
            }
            .onChange(of: value) { Haptics.selection() }
        }
    }

    @ViewBuilder
    private var title: some View {
        if !hideLabel { Text(label).typo(.caps(.label)).foregroundStyle(Palette.inkSoft).fixedSize() }
    }

    @ViewBuilder
    private var trigger: some View {
        if inForm {
            Button { choosing = true } label: { pill(chevron: 0) }
                .buttonStyle(.press)
                .accessibilityLabel("\(label), \(selected?.label ?? "")")
                .sheet(isPresented: $choosing) {
                    ChoiceList(title: label, value: $value, options: options)
                        .presentationDetents([.large])
                }
        } else {
            Menu {
                Picker(label, selection: $value) {
                    ForEach(options) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                pill(chevron: 90)
            }
            .menuOrder(.fixed)
            .buttonStyle(.plain)
            .accessibilityLabel("\(label), \(selected?.label ?? "")")
        }
    }

    private func pill(chevron: Double) -> some View {
        HStack(spacing: inline ? 8 : 12) {
            shown.frame(maxWidth: layout == .stacked ? .infinity : nil, alignment: .leading)
            Icon(.arrowRight, .bold, size: 13).foregroundStyle(Palette.ink)
                .rotationEffect(.degrees(chevron))
                .frame(width: 28, height: 28).background(Circle().fill(Palette.mist))
        }
        .padding(.leading, inline ? 10 : 18).padding(.trailing, inline ? 0 : 7)
        .frame(height: 42)
        .background { if !inline { Capsule().fill(Palette.white) } }
        .overlay { if !inline { Capsule().strokeBorder(Palette.inkLine, lineWidth: 1) } }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var shown: some View {
        if inline {
            Text(selected?.short ?? selected?.label ?? "").typo(.body(.base)).foregroundStyle(Palette.ink).lineLimit(1)
        } else {
            ZStack(alignment: .leading) {
                ForEach(options) { Text($0.label).lineLimit(1).hidden() }
                Text(selected?.label ?? "").foregroundStyle(Palette.ink).lineLimit(1)
            }
            .typo(.body(.lead))
        }
    }
}

private struct ChoiceList<Value: Hashable>: View {
    let title: String
    @Binding var value: Value
    let options: [SelectOption<Value>]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(options) { option in
                    Button {
                        value = option.value
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Text(option.label).typo(.body(.input)).foregroundStyle(Palette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if option.value == value {
                                Image(systemName: "checkmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.red)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(option.value == value ? .isSelected : [])
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Fermer")
                }
            }
        }
    }
}
