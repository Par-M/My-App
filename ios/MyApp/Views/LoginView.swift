import SwiftUI

struct LoginView: View {
    @Environment(AuthenticationService.self) private var authService
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Lock In Bud")
                    .font(.largeTitle.bold())
                Text("Sign in to continue")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await signInWithGoogle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "g.circle.fill")
                    Text("Continue with Google")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isLoading)

            Button("Development Sign In") {
                Task { await signInDev() }
            }
            .font(.footnote)
            .disabled(isLoading)

            if isLoading {
                ProgressView()
            }

            Spacer()
        }
        .padding()
        .alert(
            "Sign In Failed",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func signInWithGoogle() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await authService.signInWithGoogle()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func signInDev() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await authService.signInDev()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    LoginView()
        .environment(AuthenticationService())
}
