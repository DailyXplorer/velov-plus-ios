import SwiftUI
import VelovCore

/// Snapshot-only: the booking Live Activity drawn with the widget's own views on a mock Lock Screen or Dynamic Island,
/// since the simulator cannot be locked or have its island expanded from a script.
struct LiveActivityPreview: View {
    let island: Bool
    private let booking = SampleData.booking()
    private var attributes: BookingActivityAttributes {
        BookingActivityAttributes(bookingId: booking.id, bikeNumber: booking.bikeNumber, standNumber: booking.standNumber, stationName: booking.stationName)
    }

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
            BookingLockScreenView(attributes: attributes, endsAt: booking.endsAt!)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(ActivityStyle.red))
                .padding(.horizontal, 14)
            Spacer()
        }
    }

    private var expandedIsland: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top) {
                BookingIslandLeading(attributes: attributes)
                Spacer()
                BookingIslandTrailing(endsAt: booking.endsAt!)
            }
            BookingIslandBottom(attributes: attributes)
        }
        .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 22)
        .background(RoundedRectangle(cornerRadius: 44, style: .continuous).fill(.black))
        .padding(.horizontal, 10).padding(.top, 12)
    }
}
