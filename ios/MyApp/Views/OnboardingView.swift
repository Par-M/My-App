import SwiftUI

struct OnboardingView: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(CalendarService.self) private var calendarService
    @Environment(NotificationService.self) private var notificationService
    @Environment(ScheduleService.self) private var scheduleService

    let onComplete: () -> Void

    @State private var step = 0
    @State private var showFirstTask = false

    private static let onboardedKey = "app.onboarded"

    static var isComplete: Bool {
        UserDefaults.standard.bool(forKey: onboardedKey)
    }

    init(onComplete: @escaping () -> Void = {}) {
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $step) {
                welcomePage.tag(0)
                calendarPage.tag(1)
                notificationPage.tag(2)
                preferencePage.tag(3)
                aiPage.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.default, value: step)

            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button(continueTitle) {
                    next()
                }
                .buttonStyle(.borderedProminent)
                .disabled(continueDisabled)
            }
            .padding()
        }
        .sheet(isPresented: $showFirstTask) {
            TaskFormView(mode: .add) { _ in
                complete()
            }
        }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        pageView {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text("Lock In Bud")
                .font(.largeTitle.bold())
            Text("Your day, planned for you.\nTell us what you want to get done — the AI finds the best times.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var calendarPage: some View {
        pageView {
            Image(systemName: "calendar")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Connect your calendar")
                .font(.title2.bold())
            Text("We'll use your existing events to avoid conflicts when scheduling.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            switch calendarService.permission {
            case .granted:
                Label("Calendar access granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .denied:
                HStack {
                    Label("Calendar access needed", systemImage: "xmark.circle")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.footnote)
                }
            case .notDetermined:
                Button {
                    Task { await calendarService.requestPermission() }
                } label: {
                    Label("Enable Calendar Access", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var notificationPage: some View {
        pageView {
            Image(systemName: "bell.badge")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Get helpful reminders")
                .font(.title2.bold())
            Text("Morning briefings and deadline reminders help you stay on track.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            switch notificationService.authorizationStatus {
            case .authorized, .provisional:
                Label("Notifications enabled", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .denied:
                Label("Notifications disabled", systemImage: "bell.slash")
                    .foregroundStyle(.secondary)
            default:
                Button {
                    Task { await notificationService.requestPermission() }
                } label: {
                    Label("Enable Notifications", systemImage: "bell.badge")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var preferencePage: some View {
        pageView {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Your schedule preferences")
                .font(.title2.bold())
            Text("Set your working hours and how much the AI can pack into a day.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            PreferencesView()
                .frame(maxHeight: 420)
        }
    }

    private var aiPage: some View {
        pageView {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("How the AI works")
                .font(.title2.bold())
            Text("The scheduler considers your priorities, deadlines, energy level, and calendar to build a daily plan. It reschedules when plans change and learns your preferences over time.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showFirstTask = true
            } label: {
                Label("Create Your First Task", systemImage: "plus.circle.fill")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Helpers

    private var continueTitle: String {
        switch step {
        case 0: "Get Started"
        case 4: "Done"
        default: "Continue"
        }
    }

    private var continueDisabled: Bool {
        false
    }

    private func next() {
        if step == 4 {
            complete()
        } else {
            step += 1
        }
    }

    private func complete() {
        UserDefaults.standard.set(true, forKey: Self.onboardedKey)
        onComplete()
    }

    private func pageView<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 20) {
            content()
                .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(32)
    }
}

#Preview {
    OnboardingView()
        .environment(AuthenticationService())
        .environment(CalendarService())
        .environment(NotificationService.shared)
        .environment(ScheduleService())
}
