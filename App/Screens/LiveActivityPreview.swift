import SwiftUI
import VelovCore

struct LiveActivityPreview: View {
    let trip: Bool
    let island: Bool
    private let booking = SampleData.booking()
    private var attributes: BookingActivityAttributes {
        BookingActivityAttributes(bookingId: booking.id, bikeNumber: booking.bikeNumber, standNumber: booking.standNumber, stationName: booking.stationName)
    }
    private let ride = TripActivityAttributes.ContentState(tripId: "t-sample", startedAt: SampleData.ago(12.4 / 60), endedAt: nil,
                                                           station: SampleData.byNumber[2002]!.name, bikeNumber: 20449, bikeType: BikeType.electrical.rawValue)

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hex: 0x2b2d42), Color(hex: 0x6d597a), Color(hex: 0xb56576)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            if island { expandedIsland } else { lockScreen }
        }
        .statusBarHidden(island)
    }

    private var lockScreen: some View {
        VStack(spacing: 0) {
            Text(formatDate(SampleData.now, .dayLongMonthYear)).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white.opacity(0.85)).padding(.top, 70)
            Text("9:41").font(.system(size: 96, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.9))
            Spacer().frame(height: 300)
            Group {
                if trip { TripLockScreenView(state: ride) } else { BookingLockScreenView(attributes: attributes, endsAt: booking.endsAt!) }
            }
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(ActivityStyle.red))
            .padding(.horizontal, 14)
            Spacer()
        }
    }

    private var expandedIsland: some View {
        VStack(spacing: 18) {
            VStack(spacing: 14) {
                HStack(alignment: .top) {
                    if trip { TripIslandLeading(state: ride) } else { BookingIslandLeading(attributes: attributes) }
                    Spacer()
                    if trip { TripIslandTrailing(state: ride) } else { BookingIslandTrailing(endsAt: booking.endsAt!) }
                }
                if trip { TripIslandBottom(state: ride) } else { BookingIslandBottom(attributes: attributes) }
            }
            .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 22)
            .background(RoundedRectangle(cornerRadius: 44, style: .continuous).fill(.black))
            .padding(.horizontal, 10).padding(.top, 12)
            if trip {
                compactIsland
                minimalIsland
            }
        }
    }

    private var compactIsland: some View {
        HStack(spacing: 0) {
            Icon(.personSimpleBike, size: 18).foregroundStyle(ActivityStyle.red)
            Spacer(minLength: 126)
            TripIslandCompact(state: ride)
        }
        .padding(.horizontal, 14).frame(height: 37)
        .background(Capsule().fill(.black))
        .fixedSize()
    }

    private var minimalIsland: some View {
        HStack(spacing: 8) {
            Capsule().fill(.black).frame(width: 126, height: 37)
            Icon(.personSimpleBike, size: 18).foregroundStyle(ActivityStyle.red)
                .frame(width: 37, height: 37).background(Circle().fill(.black))
        }
    }
}
