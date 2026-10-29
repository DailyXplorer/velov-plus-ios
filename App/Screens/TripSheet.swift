import SwiftUI
import UIKit
import VelovCore

struct TripSheet: View {
    let trip: Trip
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppModel.self) private var model
    @State private var copied = false

    private var sameStation: Bool { trip.startStationNumber != nil && trip.startStationNumber == trip.endStationNumber }
    private var rated: Bool { trip.isRated == true || model.ratedHere.contains(trip.id) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Trajet").typo(.title(26)).foregroundStyle(Palette.ink)
                        Spacer()
                        IconButton(icon: .x, label: "Fermer les détails") { dismiss() }.padding(.trailing, -10).disabled(model.operations.sending)
                    }
                    times.padding(.top, 6)
                    VStack(alignment: .leading, spacing: 14) {
                        stop("Départ", trip.startStation, trip.startStand)
                        stop("Arrivée", trip.endStation, trip.endStand)
                    }
                    .padding(.top, 22)
                    facts.padding(.top, 22)
                    if let points = pointsLine { Text(points).typo(.label(13)).foregroundStyle(Palette.inkSoft).padding(.top, 10) }
                    if trip.litigious { litigious }
                    if let bike = trip.bikeNumber, !rated, canRate(trip) {
                        RateBike(trip: trip, bikeNumber: bike) {
                            model.closeEnded(trip)
                            dismiss()
                        }
                    }
                    details
                }
                .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: BikeRoute.self) { route in BikeDetail(route: route) }
        }
        .presentationDetents(model.snapshot == .rateCard ? [.large] : [.medium, .large])
        .interactiveDismissDisabled(model.operations.sending)
        .presentationBackground(Palette.white)
        .presentationDragIndicator(.visible)
        .sheetCorners()
    }

    private var times: some View {
        HStack(spacing: 0) {
            if let start = trip.startedAt {
                Text(verbatim: "\(formatDate(start, .dayLongMonthYear)) · ").typo(.body(14))
                Text(formatDate(start, .time) + (trip.endedAt.map { " → \(formatDate($0, .time))" } ?? "")).typo(.body(14))
            } else {
                Text("Date indisponible").typo(.body(14))
            }
        }
        .foregroundStyle(Palette.inkSoft)
    }

    private func stop(_ label: String, _ station: String?, _ stand: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).typo(.caps(13)).foregroundStyle(Palette.inkSoft)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(station ?? "Non renseignée").typo(.body(15)).foregroundStyle(Palette.ink)
                if let stand { Text(verbatim: "Borne \(stand)").typo(.caps(13)).foregroundStyle(Palette.inkSoft).lineLimit(1).fixedSize() }
            }
        }
    }

    private var facts: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(alignment: .top, spacing: 10) {
                fact("Durée", trip.duration.map { "\(Int($0)) min" } ?? "—")
                fact("Distance", trip.distance.flatMap { sameStation ? nil : "≈ \(formatDistance(Double($0)))" } ?? "—")
                VStack(alignment: .leading, spacing: 0) {
                    fact("Payé", trip.price.map(formatPrice) ?? "—")
                    if trip.discount > 0, let full = trip.fullPrice {
                        Text(verbatim: "Prix \(formatPrice(full)) · Remise \(formatPrice(trip.discount))").typo(.label(12)).foregroundStyle(Palette.inkSoft).padding(.top, 5)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 18)
            Hairline()
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).typo(.caps(13)).foregroundStyle(Palette.inkSoft).lineLimit(1)
            Text(value.glyphic).typo(.title(20)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        let subject = "Trajet litigieux\(trip.token.map { " \($0)" } ?? "")"
        return HStack(spacing: 12) {
            Text("Vélo’v a signalé ce trajet comme litigieux.").typo(.body(13)).foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
            Button {
                var components = URLComponents()
                components.scheme = "mailto"
                components.path = Support.address
                components.queryItems = [URLQueryItem(name: "subject", value: subject)]
                if let url = components.url { openURL(url) }
            } label: {
                Text("Contacter le service client").typo(.caps(13)).foregroundStyle(Palette.redDeep).multilineTextAlignment(.trailing)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.red, lineWidth: 1))
        .padding(.top, 14)
    }

    private var details: some View {
        Disclosure {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Eyebrow(icon: trip.bikeType == .electrical ? .lightning : .personSimpleBike,
                            text: trip.bikeType == .electrical ? "Électrique" : trip.bikeType == .mechanical ? "Mécanique" : "Vélo’v")
                    Spacer()
                    if let number = trip.bikeNumber {
                        NavigationLink(value: BikeRoute(number: number, station: nil)) {
                            HStack(spacing: 6) { Text(verbatim: "Vélo n° \(number)"); Icon(.caretRight, .bold, size: 14) }
                                .typo(.caps(14)).foregroundStyle(Palette.redDeep).frame(minHeight: 36)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 16)
                VStack(spacing: 0) {
                    if rated { DetailRow("Note du vélo", "Déjà noté") }
                    if let token = trip.token {
                        DetailRow(label: "Code du trajet") {
                            HStack(spacing: 2) {
                                Text(token).typo(.label(13))
                                IconButton(icon: copied ? .check : .copy, weight: copied ? .bold : .light, size: 16, frame: 32, label: copied ? "Code copié" : "Copier le code du trajet") {
                                    UIPasteboard.general.string = token
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    copied = true
                                }
                                .padding(.trailing, -8)
                            }
                        }
                    }
                    if trip.status != "FINISHED" { DetailRow("Statut", Messages.tripStatuses[trip.status] ?? trip.status) }
                }
                .padding(.top, 12)
            }
        }
    }
}
