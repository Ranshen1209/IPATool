import SwiftUI

struct VerificationCodeSheet: View {
    @Bindable var model: AppModel
    let prompt: AppModel.VerificationPrompt

    @State private var code = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(prompt.title)
                .font(.title3.weight(.semibold))

            Text(prompt.message)
                .foregroundStyle(.secondary)

            Text("Apple ID: \(prompt.appleID)")
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField("Two-Factor Verification Code", text: $code)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    model.cancelVerificationPrompt()
                }

                Spacer()

                Button("Continue") {
                    model.submitVerificationCode(code)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }
}
