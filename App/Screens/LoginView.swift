import SwiftUI
import VelovCore

struct LoginView: View {
    let notice: String?
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var code = ""
    @State private var pending = false
    @State private var failure: LoadFailure?
    @FocusState private var focus: Field?

    enum Field { case email, code }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                (Text("Vélo’v").foregroundStyle(Palette.ink) + Text("+").foregroundStyle(Palette.red)).typo(.title(.display))
                VStack(spacing: Space.cards) {
                    field {
                        TextField("", text: $email, prompt: Text("Adresse e-mail").foregroundStyle(Palette.inkSoft))
                            .textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .submitLabel(.next).focused($focus, equals: .email).onSubmit { focus = .code }
                            .accessibilityLabel("Adresse e-mail")
                    }
                    field {
                        SecureField("", text: $code, prompt: Text("Code secret").foregroundStyle(Palette.inkSoft))
                            .textContentType(.password).keyboardType(.numberPad).focused($focus, equals: .code)
                            .onChange(of: code) { _, value in
                                let digits = String(value.filter(\.isNumber).prefix(6))
                                if digits != value { code = digits }
                            }
                            .accessibilityLabel("Code secret à 6 chiffres")
                    }
                    PillButton("Se connecter", pending: pending, fullWidth: true) { submit() }
                        .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || code.count != 6)
                        .padding(.top, Space.pair)
                    VStack(alignment: .leading, spacing: Space.pair) {
                        if let failure {
                            FormError(failure.message)
                            if !failure.raw.isEmpty { RawStatus(line: failure.raw) }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: Space.state, alignment: .topLeading)
                }
                .padding(.top, Space.section)
            }
            .frame(maxWidth: 340)
            .padding(.horizontal, Layout.margin)
            .frame(maxHeight: .infinity)
            if let notice {
                Text(notice).typo(.body(.small)).foregroundStyle(Palette.inkSoft).multilineTextAlignment(.center).padding(.horizontal, Layout.margin).padding(.top, Layout.headerTop)
            }
        }
        .background(Palette.white)
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .typo(.body(.input))
            .foregroundStyle(Palette.ink)
            .disabled(pending)
            .fieldPill()
    }

    private func submit() {
        guard !pending else { return }
        pending = true
        failure = nil
        focus = nil
        Task {
            defer { pending = false }
            do {
                try await model.signIn(email: email.trimmingCharacters(in: .whitespaces), code: code)
                code = ""
            } catch {
                Haptics.refused()
                failure = LoadFailure(error, "Connexion impossible. Vérifiez votre connexion Internet.")
            }
        }
    }
}
