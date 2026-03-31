import SwiftUI

struct AuthView: View {
    @Bindable var model: AppModel

    @State private var appleID = ""
    @State private var password = ""

    var body: some View {
        Form {
            Section("Session") {
                switch model.sessionState {
                case .signedOut:
                    Label("Signed Out", systemImage: "person.crop.circle.badge.xmark")
                case .signingIn:
                    HStack {
                        ProgressView()
                        Text("Signing In")
                    }
                case .signedIn(let session):
                    VStack(alignment: .leading, spacing: 6) {
                        Label(session.displayName, systemImage: "checkmark.seal")
                        Text(session.appleID)
                            .foregroundStyle(.secondary)
                        if let storeFront = session.storeFront {
                            Text("Storefront: \(storeFront)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                case .failed(let error):
                    VStack(alignment: .leading, spacing: 6) {
                        Label(error.title, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(error.message)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Credentials") {
                TextField("Apple ID", text: $appleID)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                if !model.cachedAppleID.isEmpty {
                    Text("Cached Apple ID: \(model.cachedAppleID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Verification") {
                Text("IPATool now requests the Apple verification code only when Apple explicitly challenges the session.")
                Text("If a previously saved verification code is still valid, the app will reuse it automatically. When it expires, a separate verification sheet will appear so you can enter the new code.")
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Sign In") {
                        Task {
                            await model.signIn(appleID: appleID, password: password, code: "")
                        }
                    }
                    .disabled(appleID.isEmpty || password.isEmpty || model.sessionState == .signingIn)

                    Button("Sign Out") {
                        Task {
                            await model.signOut()
                        }
                    }
                    .disabled({
                        if case .signedIn = model.sessionState {
                            return false
                        }
                        return true
                    }())
                }
            } footer: {
                Text("Sign-in uses the private Apple authentication flow from the original tool. Two-factor verification is handled as a follow-up challenge instead of an always-visible form field.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Account")
        .task {
            if appleID.isEmpty {
                appleID = model.cachedAppleID
            }
        }
    }
}
