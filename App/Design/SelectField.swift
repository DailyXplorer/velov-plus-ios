import SwiftUI

struct SelectOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var id: Value { value }
}

/// `SelectField` of ui.tsx: a mono label, a grey field and the web's own dropdown (white card, check on the chosen option),
/// not the iOS menu. The row that holds it needs `.zIndex(1)` so the list draws over what follows.
struct SelectField<Value: Hashable>: View {
    let label: String
    @Binding var value: Value
    let options: [SelectOption<Value>]
    var background = Palette.fieldFill
    @State private var open = false

    private var selected: SelectOption<Value>? { options.first { $0.value == value } ?? options.first }

    var body: some View {
        HStack(spacing: 10) {
            Text(label).typo(.label(11)).foregroundStyle(Palette.inkSoft).fixedSize()
            Button { withAnimation(.easeOut(duration: 0.16)) { open.toggle() } } label: {
                HStack(spacing: 10) {
                    Text(selected?.label ?? "").typo(.body(16)).foregroundStyle(Palette.ink).lineLimit(1)
                    Icon(.caretDown, .light, size: 14).foregroundStyle(Palette.inkSoft).rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.leading, 11.25).padding(.trailing, 12)
                .frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 5.625).fill(background))
                .overlay(RoundedRectangle(cornerRadius: 5.625).strokeBorder(Palette.fieldLine, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(label), \(selected?.label ?? "")")
            .overlay(alignment: .topLeading) {
                if open {
                    list.offset(y: 48).transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
        }
        .zIndex(open ? 100 : 0)
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(options) { option in
                Button {
                    value = option.value
                    withAnimation(.easeOut(duration: 0.16)) { open = false }
                } label: {
                    HStack(spacing: 16) {
                        Text(option.label).typo(.body(14)).lineLimit(1)
                        Spacer(minLength: 0)
                        if option.value == value { Icon(.check, .bold, size: 16) }
                    }
                    .foregroundStyle(option.value == value ? Palette.red : Palette.ink)
                    .padding(.horizontal, 12).frame(minHeight: 40)
                    .background(RoundedRectangle(cornerRadius: 10).fill(option.value == value ? Palette.mist : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(width: 220)
        .background(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous).fill(Palette.white))
        .overlay(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .shadow(color: Palette.ink.opacity(0.1), radius: 18, y: 12)
        .fixedSize(horizontal: false, vertical: true)
    }
}
