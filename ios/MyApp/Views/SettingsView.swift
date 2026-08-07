import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(CalendarService.self) private var calendarService
    @Environment(NotificationService.self) private var notificationService
    @Environment(ScheduleService.self) private var scheduleService
    @Environment(TaskService.self) private var taskService
    @Environment(SyncManager.self) private var syncManager
    @Environment(CategoryStore.self) private var categoryStore
    @Environment(AppearanceSettings.self) private var appearance

    @State private var showNotificationSettings = false
    @State private var showPreferences = false
    @State private var newCategory = ""
    @State private var syncedMessage = false

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                schedulingSection
                calendarSection
                notificationSection
                appearanceSection
                categoriesSection
                privacySection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section("Account") {
            if let user = authService.user {
                if let name = user.name {
                    LabeledContent("Name", value: name)
                }
                if let email = user.email {
                    LabeledContent("Email", value: email)
                }
            }
            Button("Sign Out", role: .destructive) {
                authService.signOut()
            }
        }
    }

    private var schedulingSection: some View {
        Section("Scheduling") {
            Button {
                showPreferences = true
            } label: {
                LabeledContent {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Schedule Preferences", systemImage: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showPreferences) {
            PreferencesView()
        }
    }

    private var calendarSection: some View {
        Section("Calendar") {
            switch calendarService.permission {
            case .granted:
                Label("Calendar connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                NavigationLink {
                    CalendarSelectionView()
                } label: {
                    Label("Choose Calendars", systemImage: "checklist")
                }
            case .denied:
                HStack {
                    Label("Calendar access disabled", systemImage: "calendar.badge.exclamationmark")
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
                    Label("Connect Calendar", systemImage: "calendar.badge.plus")
                }
            }

            Button {
                Task { await syncNow() }
            } label: {
                if syncManager.isSyncing {
                    HStack {
                        ProgressView()
                        Text("Syncing…")
                    }
                } else {
                    HStack {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if syncManager.pendingCount > 0 {
                            Text("\(syncManager.pendingCount) pending")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .disabled(syncManager.isSyncing)

            if let lastSync = syncManager.lastSyncDate {
                LabeledContent("Last synced", value: lastSync.formatted(date: .abbreviated, time: .shortened))
            }
            if syncedMessage, syncManager.lastSyncError == nil {
                Label("Sync complete", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let error = syncManager.lastSyncError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var notificationSection: some View {
        Section("Notifications") {
            Button {
                showNotificationSettings = true
            } label: {
                LabeledContent {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Notification Settings", systemImage: "bell")
                }
            }
        }
        .sheet(isPresented: $showNotificationSettings) {
            NavigationStack {
                NotificationSettingsView()
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: Bindable(appearance).theme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.label).tag(theme)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var categoriesSection: some View {
        Section("Categories") {
            ForEach(categoryStore.categories(from: taskService.tasks), id: \.self) { category in
                HStack {
                    Text(category)
                    Spacer()
                    Button {
                        categoryStore.remove(category)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack {
                TextField("New category", text: $newCategory)
                Button("Add") {
                    categoryStore.add(newCategory)
                    newCategory = ""
                }
                .disabled(newCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            Text("Schedule generation is powered by Google's Gemini AI. Task details you create are sent to the scheduler to plan your day. Calendar events are never uploaded — only busy-time blocks you choose to share.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func syncNow() async {
        syncedMessage = false
        await syncManager.syncNow()
        if syncManager.lastSyncError == nil {
            syncedMessage = true
        }
    }
}

#Preview {
    SettingsView()
        .environment(AuthenticationService())
        .environment(CalendarService())
        .environment(NotificationService.shared)
        .environment(ScheduleService())
        .environment(TaskService())
        .environment(SyncManager(store: LocalStore(inMemory: true), connectivity: ConnectivityMonitor()))
        .environment(CategoryStore())
        .environment(AppearanceSettings())
}
