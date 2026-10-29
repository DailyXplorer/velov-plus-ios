import SwiftUI
import VelovCore

@main
struct VelovApp: App {
    @State private var model: AppModel

    init() {
        FontBook.register()
        let defaults = UserDefaults.standard
        let snapshot = defaults.string(forKey: "VelovScreen").flatMap(SnapshotScreen.init)
        let sample = defaults.bool(forKey: "VelovSample") || snapshot != nil
        _model = State(initialValue: AppModel(service: sample ? SampleService() : LiveService(), snapshot: snapshot))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.light)
                .tint(Palette.red)
                .task { await model.start() }
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
            Shell()
        }
    }
}
