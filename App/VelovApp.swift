import SwiftUI
import VelovCore

@main
struct VelovApp: App {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FontBook.register()
        let defaults = UserDefaults.standard
        let snapshot = defaults.string(forKey: "VelovScreen").flatMap(SnapshotScreen.init)
        let sample = defaults.bool(forKey: "VelovSample") || snapshot != nil
        let service: VelovService = sample ? SampleService(booking: snapshot?.withBooking == true ? SampleData.booking() : nil) : LiveService()
        let promos: PromoBacking = sample ? InMemoryPromoBacking() : FilePromoBacking(directory: AppModel.promoDirectory())
        _model = State(initialValue: AppModel(service: service, snapshot: snapshot, promoBacking: promos))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.light)
                .tint(Palette.red)
                .task { await model.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.becameActive() }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.phase {
        case .launching:
            Palette.white.ignoresSafeArea()
        case .guest(let message):
            LoginView(notice: message)
        default:
            if model.snapshot == .liveActivityLock || model.snapshot == .liveActivityIsland {
                LiveActivityPreview(island: model.snapshot == .liveActivityIsland)
            } else {
                Shell()
            }
        }
    }
}
