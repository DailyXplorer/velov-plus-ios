import SwiftUI
import VelovCore

struct JournalLink: View {
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Les \(TechnicalJournal.capacity) dernières requêtes envoyées à Vélo’v, sans jeton ni donnée personnelle.")
                .typo(.body(.base)).foregroundStyle(Palette.inkSoft).fixedSize(horizontal: false, vertical: true)
            PillButton("Ouvrir le journal", variant: .secondary) { open = true }
        }
        .sheet(isPresented: $open) { JournalSheet() }
    }
}

struct JournalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries = TechnicalJournal.shared.entries
    @State private var clearing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeading(title: "Journal technique") { dismiss() }
            if entries.isEmpty {
                StateView("Aucune requête enregistrée.")
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(entries.indices, id: \.self) { JournalRow(entry: entries[$0]) }
                    }
                }
                .scrollIndicators(.visible)
                .padding(.top, 10)
            }
            PairedActions {
                PillButton("Effacer", variant: .ghost, fullWidth: true) { clearing = true }
                    .disabled(entries.isEmpty)
                ShareLink(item: TechnicalJournal.shared.export()) {
                    HStack(spacing: 10) { ButtonIcon(.share); Text("Partager") }
                        .typo(.caps(.button)).foregroundStyle(entries.isEmpty ? Palette.inkSoft : Palette.white)
                        .frame(maxWidth: .infinity, minHeight: Layout.control)
                        .background(Capsule().fill(entries.isEmpty ? Palette.mist : Palette.red))
                        .contentShape(Capsule())
                }
                .buttonStyle(.press)
                .disabled(entries.isEmpty)
            }
            .padding(.top, Space.actions)
            .confirmationDialog("Effacer le journal\u{a0}?", isPresented: $clearing, titleVisibility: .visible) {
                Button("Effacer", role: .destructive) {
                    TechnicalJournal.shared.clear()
                    entries = []
                }
                Button("Annuler", role: .cancel) {}
            }
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 20)
        .presentationDetents([.large])
        .presentationBackground(Palette.white)
        .presentationDragIndicator(.hidden)
        .sheetCorners()
    }
}

private struct JournalRow: View {
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.at.formatted(Date.FormatStyle(date: .numeric, time: .standard).locale(Locale(identifier: "fr_FR"))))
                    .typo(.body(.meta)).foregroundStyle(Palette.inkSoft)
                Spacer(minLength: 0)
                Text(entry.result).typo(.label(.meta)).foregroundStyle(entry.status.map { $0 < 400 } == true ? Palette.ink : Palette.formError)
            }
            Text(verbatim: "\(entry.method) \(entry.path)").typo(.label(.meta)).foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Text(verbatim: ([entry.milliseconds] + [entry.operation].compactMap { $0 }).joined(separator: " · "))
                .typo(.body(.meta)).foregroundStyle(Palette.inkSoft)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Hairline() }
    }
}
