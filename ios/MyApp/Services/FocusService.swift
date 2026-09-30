import Foundation
import Observation

@MainActor
@Observable
final class FocusService {
    private(set) var dailySessions: [FocusSession] = []
    private(set) var reflections: [Reflection] = []
    private(set) var summary: FocusSummary?
    private(set) var morningMessage: MorningMessage?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var dataVersion = 0
    private(set) var pendingSessions: [PendingFocusSession] = []

    private let client: APIClient
    private let pendingStore: PendingFocusSessionStore

    init(client: APIClient? = nil, pendingStore: PendingFocusSessionStore? = nil) {
        self.client = client ?? APIClient()
        self.pendingStore = pendingStore ?? PendingFocusSessionStore()
        self.pendingSessions = self.pendingStore.load()
    }

    func loadFocus(after: Date? = nil, before: Date? = nil) async {
        isLoading = true
        defer { isLoading = false }
        async let sessions = loadSessions(after: after, before: before)
        async let summary = loadSummary(after: after, before: before)
        async let reflections = loadReflections()
        _ = await (sessions, summary, reflections)
    }

    @discardableResult
    func createSession(
        taskID: UUID?,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Int? = nil,
        category: String? = nil
    ) async -> FocusSession? {
        let payload = FocusSessionCreate(
            taskID: taskID,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            category: category
        )
        do {
            let session: FocusSession = try await client.request(FocusEndpoint.create(payload))
            dataVersion += 1
            await loadFocus()
            return session
        } catch {
            // Keep the session safe locally so a stalled upload never loses the
            // work. It is replayed by flushPendingSessions() once the device is
            // back online (foreground or after a successful refresh).
            enqueuePending(
                PendingFocusSession(
                    taskID: taskID,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    durationSeconds: durationSeconds,
                    category: category
                )
            )
            errorMessage = "Focus session saved on this device. It will sync when you're back online."
            return nil
        }
    }

    /// Uploads every locally queued focus session.
    ///
    /// Called when the app returns to the foreground and after a successful
    /// token refresh so sessions recorded while offline or while the session
    /// had lapsed are not silently dropped.
    func flushPendingSessions() async {
        let pending = pendingSessions
        guard !pending.isEmpty else { return }

        var remaining = pending
        var flushed: [PendingFocusSession] = []
        for queued in pending {
            do {
                let payload = FocusSessionCreate(
                    taskID: queued.taskID,
                    startedAt: queued.startedAt,
                    endedAt: queued.endedAt,
                    durationSeconds: queued.durationSeconds,
                    category: queued.category
                )
                _ = try await client.request(FocusEndpoint.create(payload)) as FocusSession
                flushed.append(queued)
                remaining.removeAll { $0.id == queued.id }
            } catch {
                // Keep it queued; the next foreground will retry.
            }
        }

        guard !flushed.isEmpty else { return }
        pendingSessions = remaining
        pendingStore.save(remaining)
        dataVersion += 1
        await loadFocus()
        if !pendingSessions.isEmpty {
            errorMessage = "Some focus sessions are waiting to sync."
        } else {
            errorMessage = nil
        }
    }

    private func enqueuePending(_ session: PendingFocusSession) {
        guard !pendingSessions.contains(where: { $0.id == session.id }) else { return }
        pendingSessions.append(session)
        pendingStore.save(pendingSessions)
    }

    @discardableResult
    func updateSession(
        id: UUID,
        startedAt: Date?,
        endedAt: Date?
    ) async -> FocusSession? {
        let payload = FocusSessionUpdate(startedAt: startedAt, endedAt: endedAt)
        do {
            let session: FocusSession = try await client.request(
                FocusEndpoint.update(id: id, payload)
            )
            dataVersion += 1
            await loadFocus()
            return session
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func deleteSession(id: UUID) async -> Bool {
        do {
            _ = try await client.request(FocusEndpoint.delete(id)) as MessageResponse
            dailySessions.removeAll { $0.id == id }
            dataVersion += 1
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func createReflection(date: Date, text: String) async -> Reflection? {
        let payload = ReflectionCreate(date: date, text: text)
        do {
            let reflection: Reflection = try await client.request(FocusEndpoint.createReflection(payload))
            dataVersion += 1
            await loadReflections()
            return reflection
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func loadMorningMessage() async -> MorningMessage? {
        do {
            let message: MorningMessage = try await client.request(FocusEndpoint.morningMessage)
            morningMessage = message
            dataVersion += 1
            return message
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func loadSessions(after: Date? = nil, before: Date? = nil) async {
        do {
            let response: [FocusSession] = try await client.request(FocusEndpoint.sessions)
            dailySessions = response
            dataVersion += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadSummary(after: Date? = nil, before: Date? = nil) async {
        do {
            let response: FocusSummary = try await client.request(
                FocusEndpoint.summary(after: after, before: before)
            )
            summary = response
            dataVersion += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadReflections() async {
        do {
            let response: [Reflection] = try await client.request(FocusEndpoint.reflections)
            reflections = response
            dataVersion += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A focus session that was stopped locally but could not be uploaded yet.
struct PendingFocusSession: Codable, Identifiable, Sendable {
    let id: UUID
    let taskID: UUID?
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Int?
    let category: String?

    init(
        id: UUID = UUID(),
        taskID: UUID?,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Int?,
        category: String?
    ) {
        self.id = id
        self.taskID = taskID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.category = category
    }
}

/// Durable file-backed store for focus sessions waiting to sync.
final class PendingFocusSessionStore {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("MyApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = fileURL ?? directory.appendingPathComponent("PendingFocusSessions.json")
    }

    func load() -> [PendingFocusSession] {
        guard let data = try? Data(contentsOf: fileURL),
              let sessions = try? JSONDecoder().decode([PendingFocusSession].self, from: data) else {
            return []
        }
        return sessions
    }

    func save(_ sessions: [PendingFocusSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
