import SwiftUI
import VelovCore

struct JournalLink: View {
    @Environment(AppModel.self) private var model

    static let caption = "Les \(TechnicalJournal.capacity) dernières lectures et les \(TechnicalJournal.writeCapacity) dernières actions (gardées \(TechnicalJournal.writeRetentionDays) jours) envoyées à Vélo’v, sans jeton ni donnée personnelle."

    var body: some View {
        VStack(alignment: .leading, spacing: Space.titleToContent) {
            Text(Self.caption)
                .typo(.body(.base)).foregroundStyle(Palette.inkSoft).fixedSize(horizontal: false, vertical: true)
            PillButton(variant: .secondary, action: { model.push(.journal, on: .account) }) { ButtonIcon(.file); Text("Ouvrir le journal") }
        }
    }
}

struct JournalPage: View {
    @Environment(AppModel.self) private var model
    @State private var entries: [JournalEntry] = []
    @State private var clearing = false

    private var journal: TechnicalJournal { model.snapshot == nil ? .shared : SampleData.journal }

    var body: some View {
        PushedPage("Journal technique") {
            if entries.isEmpty {
                StateView("Aucune requête enregistrée.")
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(entries.indices, id: \.self) { JournalRow(entry: entries[$0]) }
                }
            }
            PairedActions {
                PillButton("Effacer", variant: .ghost, fullWidth: true) { clearing = true }
                    .disabled(entries.isEmpty)
                ShareLink(item: journal.export()) {
                    PillLabel(fullWidth: true) { ButtonIcon(.share); Text("Partager") }
                }
                .buttonStyle(.press)
                .disabled(entries.isEmpty)
            }
            .padding(.top, Space.actions)
        }
        .task { entries = journal.entries }
        .confirmationDialog("Effacer le journal\u{a0}?", isPresented: $clearing, titleVisibility: .visible) {
            Button("Effacer", role: .destructive) {
                journal.clear()
                entries = []
            }
            Button("Annuler", role: .cancel) {}
        }
    }
}

private struct JournalRow: View {
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Space.pair) {
            HStack(alignment: .firstTextBaseline, spacing: Space.label) {
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
        .padding(.vertical, Space.cards)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Hairline() }
    }
}
