import SwiftUI
import UIKit
import VelovCore

struct TripPage: View {
    let trip: Trip
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var copied = false

    private var sameStation: Bool { trip.startStationNumber != nil && trip.startStationNumber == trip.endStationNumber }
    private var rated: Bool { trip.isRated == true || model.ratedHere.contains(trip.id) }

    var body: some View {
        PushedPage(title: "Trajet") {
            VStack(alignment: .leading, spacing: Space.label) {
                PageTitle(title: "Trajet")
                tripTimes(trip)
            }
        } content: {
            VStack(alignment: .leading, spacing: Space.row) {
                stop("Départ", trip.startStation, trip.startStand)
                stop("Arrivée", trip.endStation, trip.endStand)
            }
            facts.padding(.top, Layout.headerBottom)
            if let points = pointsLine { Text(points).typo(.label(.small)).foregroundStyle(Palette.inkSoft).padding(.top, Space.cards) }
            if trip.litigious { litigious }
            if let bike = trip.bikeNumber, !rated, canRate(trip) {
                RateBike(trip: trip, bikeNumber: bike) {
                    model.closeEnded(trip)
                    dismiss()
                }
                .padding(.top, Space.cards)
            }
            details.padding(.top, Space.label)
        }
    }

    private func stop(_ label: String, _ station: String?, _ stand: Int?) -> some View {
        VStack(alignment: .leading, spacing: Space.pair) {
            Text(label).typo(.caps(.label)).foregroundStyle(Palette.inkSoft)
            HStack(alignment: .firstTextBaseline, spacing: Space.label) {
                Text(station ?? "Non renseignée").typo(.body(.lead)).foregroundStyle(Palette.ink)
                if let stand { Text(verbatim: "Borne \(stand)").typo(.caps(.label)).foregroundStyle(Palette.inkSoft).lineLimit(1).fixedSize() }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var facts: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(alignment: .top, spacing: Space.cards) {
                TripFact(label: "Durée", value: trip.duration.map(formatMinutes) ?? "—")
                TripFact(label: "Distance", value: trip.distance.flatMap { sameStation ? nil : "≈ \(formatDistance(Double($0)))" } ?? "—")
                VStack(alignment: .leading, spacing: 0) {
                    TripFact(label: "Payé", value: trip.price.map(formatPrice) ?? "—")
                    if trip.discount > 0, let full = trip.fullPrice {
                        Text(verbatim: "Prix \(formatPrice(full)) · Remise \(formatPrice(trip.discount))").typo(.label(.meta)).foregroundStyle(Palette.inkSoft).padding(.top, Space.pair)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Space.row)
            Hairline()
        }
    }

    private var pointsLine: String? {
        let earned = Int(trip.pointsEarned), spent = Int(trip.pointsSpent)
        let points = { (count: Int) in "\(formatNumber(count)) point\(count > 1 ? "s" : "")" }
        if earned > 0 && spent > 0 { return "+\(points(earned)) gagné\(earned > 1 ? "s" : "") · \(formatNumber(spent)) dépensé\(spent > 1 ? "s" : "")" }
        if earned > 0 { return "+\(points(earned)) gagné\(earned > 1 ? "s" : "")" }
        if spent > 0 { return "\(points(spent)) dépensé\(spent > 1 ? "s" : "")" }
        return nil
    }

    private var litigious: some View {
        VStack(alignment: .leading, spacing: Space.cards) {
            Text("Vélo’v a signalé ce trajet comme litigieux.").typo(.body(.small)).foregroundStyle(Palette.ink)
            PillButton(variant: .secondary, action: contact) { ButtonIcon(.envelopeSimple); Text("Écrire au service client") }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(.ringed, compact: true)
        .padding(.top, Space.titleToContent)
    }

    private func contact() {
        model.contactRequest = ContactRequest(trip: TripRoute(trip: trip))
        model.page = .account
    }

    private var details: some View {
        Disclosure {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Eyebrow(icon: trip.bikeType == .electrical ? .lightning : .personSimpleBike,
                            text: trip.bikeType == .electrical ? "Électrique" : trip.bikeType == .mechanical ? "Mécanique" : "Vélo’v")
                    Spacer()
                    if let number = trip.bikeNumber {
                        NavigationLink(value: Route.bike(BikeRoute(number: number, station: nil))) {
                            TextLinkLabel(title: "Vélo \(number)", trailing: .caret)
                        }
                        .buttonStyle(.press)
                    }
                }
                .padding(.top, Space.label)
                VStack(spacing: 0) {
                    if rated { DetailRow("Note du vélo", "Déjà noté") }
                    if let token = trip.token {
                        DetailRow(label: "Code du trajet") {
                            HStack(spacing: Space.pair) {
                                Text(token).typo(.label(.small))
                                IconButton(icon: copied ? .check : .copy, weight: copied ? .bold : .light, label: copied ? "Code copié" : "Copier le code du trajet") {
                                    UIPasteboard.general.string = token
                                    Haptics.success()
                                    withAnimation(Motion.standard) { copied = true }
                                }
                                .bleed(.trailing)
                            }
                        }
                    }
                    if trip.status != "FINISHED" { DetailRow("Statut", Messages.tripStatuses[trip.status] ?? "Inconnu") }
                }
                .padding(.top, Space.label)
            }
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            withAnimation(Motion.standard) { copied = false }
        }
    }
}

struct TripFact: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: Space.label) {
            Text(label).typo(.caps(.label)).foregroundStyle(Palette.inkSoft).lineLimit(1)
            Text(value.glyphic).typo(.title(.card)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
