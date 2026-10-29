import SwiftUI
import VelovCore

/// login.tsx: the e-mail and the 6-digit secret code, one attempt per tap.
struct LoginView: View {
    let notice: String?
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var code = ""
    @State private var pending = false
    @State private var error = ""
    @FocusState private var focus: Field?

    enum Field { case email, code }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                (Text("Vélo’v").foregroundStyle(Palette.ink) + Text("+").foregroundStyle(Palette.red)).typo(.title(48))
                VStack(spacing: 12) {
                    field {
                        TextField("", text: $email, prompt: Text("Adresse email").foregroundStyle(Palette.inkFaint))
                            .textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .submitLabel(.next).focused($focus, equals: .email).onSubmit { focus = .code }
                            .accessibilityLabel("Adresse email")
                    }
                    field {
                        SecureField("", text: $code, prompt: Text("Code secret").foregroundStyle(Palette.inkFaint))
                            .textContentType(.password).keyboardType(.numberPad).focused($focus, equals: .code)
                            .onChange(of: code) { _, value in
                                let digits = String(value.filter(\.isNumber).prefix(6))
                                if digits != value { code = digits }
                            }
                            .accessibilityLabel("Code secret à 6 chiffres")
                    }
                    PillButton("Se connecter", pending: pending, fullWidth: true) { submit() }
                        .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || code.count != 6)
                        .padding(.top, 6)
                    Text(error).typo(.body(13)).foregroundStyle(Palette.formError).frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
                        .opacity(error.isEmpty ? 0 : 1)
                }
                .padding(.top, 36)
            }
            .frame(maxWidth: 340)
            .padding(.horizontal, 24)
            .frame(maxHeight: .infinity)
            if let notice {
                Text(notice).typo(.body(13)).foregroundStyle(Palette.inkSoft).multilineTextAlignment(.center).padding(.horizontal, 24).padding(.top, 24)
            }
        }
        .background(Palette.white)
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .typo(.body(16))
            .foregroundStyle(Palette.ink)
            .disabled(pending)
            .padding(.horizontal, 11.25)
            .frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 5.625).fill(Palette.fieldFill))
            .overlay(RoundedRectangle(cornerRadius: 5.625).strokeBorder(Palette.fieldLine, lineWidth: 1))
    }

    private func submit() {
        guard !pending else { return }
        pending = true
        error = ""
        focus = nil
        Task {
            defer { pending = false }
            do {
                try await model.signIn(email: email.trimmingCharacters(in: .whitespaces), code: code)
                code = ""
            } catch let failure as VelovError {
                error = failure.message
            } catch {
                self.error = "Connexion impossible. Vérifiez votre accès à Internet."
            }
        }
    }
}
