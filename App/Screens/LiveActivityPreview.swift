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
                                                           station: SampleData.byNumber[2002]!.name, bikeNumber: 20449)

    var body: some View {
        ZStack(alignment: .top) {
            Wallpaper()
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

private struct Wallpaper: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.6, 0.42], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ], colors: [
                    Color(hex: 0x161c27), Color(hex: 0x1b2330), Color(hex: 0x212b3a),
                    Color(hex: 0x293648), Color(hex: 0x3a4a60), Color(hex: 0x2b3747),
                    Color(hex: 0x171d27), Color(hex: 0x222d3d), Color(hex: 0x141922),
                ])
                glow(Color(hex: 0x3d5070), opacity: 0.45, width: w * 0.9, height: w * 0.9, angle: 0, blur: 80, at: CGPoint(x: w * 0.05, y: h * 0.1))
                glow(Color(hex: 0x7d94ad), opacity: 0.42, width: w * 1.7, height: w * 0.55, angle: -38, blur: 60, at: CGPoint(x: w * 0.66, y: h * 0.5))
                glow(Color(hex: 0x4b6380), opacity: 0.5, width: w * 1.5, height: w * 0.36, angle: -38, blur: 50, at: CGPoint(x: w * 0.28, y: h * 0.8))
                glow(Color(hex: 0xdde6ef), opacity: 0.15, width: w * 1.3, height: w * 0.09, angle: -38, blur: 22, at: CGPoint(x: w * 0.74, y: h * 0.43))
                RadialGradient(colors: [.clear, .black.opacity(0.4)], center: UnitPoint(x: 0.55, y: 0.45), startRadius: w * 0.3, endRadius: h * 0.75)
                Image(decorative: Self.grain, scale: 3).resizable(resizingMode: .tile).blendMode(.overlay).opacity(0.12)
            }
        }
        .ignoresSafeArea()
    }

    private func glow(_ color: Color, opacity: Double, width: CGFloat, height: CGFloat, angle: Double, blur: CGFloat, at point: CGPoint) -> some View {
        Ellipse().fill(color.opacity(opacity)).frame(width: width, height: height).rotationEffect(.degrees(angle)).blur(radius: blur).position(point)
    }

    private static let grain: CGImage = {
        let side = 256
        var state: UInt64 = 0x9e3779b97f4a7c15
        let bytes = (0..<side * side).map { _ -> UInt8 in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return UInt8(truncatingIfNeeded: state >> 56)
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }()
}
