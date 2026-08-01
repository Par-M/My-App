import SwiftUI

struct DashboardView: View {
    @Environment(AuthenticationService.self) private var authService

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)

                Text(authService.user?.name ?? "Signed in")
                    .font(.title.bold())

                Text(authService.user?.email ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Log Out", role: .destructive) {
                    authService.signOut()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 24)
            }
            .padding()
            .navigationTitle("Dashboard")
        }
    }
}

#Preview {
    DashboardView()
        .environment(AuthenticationService())
}
