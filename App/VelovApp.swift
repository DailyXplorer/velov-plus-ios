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
        let service: VelovService = sample ? SampleService(screen: snapshot, slow: defaults.bool(forKey: "VelovSlow")) : LiveService()
        let promos: PromoBacking = sample ? InMemoryPromoBacking() : FilePromoBacking(directory: AppModel.promoDirectory())
        let operations: OperationBacking = sample ? InMemoryOperationBacking() : DefaultsOperationBacking()
        let guest = sample ? SampleData.guestStore(snapshot) : GuestStore(defaults: defaults)
        _model = State(initialValue: AppModel(service: service, snapshot: snapshot, promoBacking: promos, operationBacking: operations, guestStore: guest))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(model.snapshot?.isLiveActivity == true ? .dark : .light)
                .tint(Palette.red)
                .task { await model.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.becameActive() } else { model.resignedActive() }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.phase {
        case .launching:
            Palette.white.ignoresSafeArea()
        case .signedOut(let message):
            LoginView(notice: message)
        case .guest:
            GuestShell()
        default:
            if let screen = model.snapshot, screen.isLiveActivity {
                LiveActivityPreview(trip: [.tripActivityLock, .tripActivityIsland].contains(screen), island: [.liveActivityIsland, .tripActivityIsland].contains(screen))
            } else {
                Shell()
            }
        }
    }
}
