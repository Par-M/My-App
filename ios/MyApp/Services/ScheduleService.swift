import Foundation
import Observation

@MainActor
@Observable
final class ScheduleService {
    private(set) var proposal: ScheduleProposal?
    private(set) var blocks: [CalendarBlock] = []
    private(set) var preference: UserPreference?
    private(set) var isGenerating = false
    private(set) var isSyncing = false
    private(set) var errorMessage: String?

    private let client: APIClient
    private let calendarService: CalendarService
    private let store: LocalStore?
    private let connectivity: ConnectivityMonitor

    init(
        client: APIClient? = nil,
        calendarService: CalendarService? = nil,
        store: LocalStore? = nil,
        connectivity: ConnectivityMonitor? = nil
    ) {
        self.client = client ?? APIClient()
        self.calendarService = calendarService ?? CalendarService()
        self.store = store
        self.connectivity = connectivity ?? ConnectivityMonitor()
    }

    func loadBlocks() async {
        do {
            let response: CalendarBlockListResponse = try await client.request(
                CalendarEndpoint.listBlocks()
            )
            blocks = response.items.sorted { $0.startAt < $1.startAt }
            store?.upsertServerBlocks(response.items)
        } catch {
            if let store, isNetworkUnavailable(error) || !connectivity.isConnected {
                blocks = store.blocks()
                errorMessage = "Offline — showing saved schedule."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func presentError(_ message: String) {
        errorMessage = message
    }

    func loadPreferences() async {
        do {
            preference = try await client.request(PreferenceEndpoint.get)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updatePreferences(_ update: UserPreferenceUpdate) async {
        do {
            preference = try await client.request(PreferenceEndpoint.update(update))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func generate(startDate: Date, endDate: Date, busyTimes: [BusyTimeRequest] = []) async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        do {
            let request = ScheduleGenerateRequest(
                startDate: startDate,
                endDate: endDate,
                timezone: TimeZone.current.identifier,
                busyTimes: busyTimes
            )
            let response: ScheduleProposal = try await client.request(
                ScheduleEndpoint.generate(request)
            )
            proposal = response
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func replan(startDate: Date, endDate: Date, busyTimes: [BusyTimeRequest] = []) async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        do {
            let request = ScheduleGenerateRequest(
                startDate: startDate,
                endDate: endDate,
                timezone: TimeZone.current.identifier,
                busyTimes: busyTimes
            )
            let response: ScheduleProposal = try await client.request(
                ScheduleEndpoint.replan(request)
            )
            proposal = response
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func accept(_ target: ScheduleProposal) async throws {
        errorMessage = nil
        let response: AcceptResponse = try await client.request(
            ScheduleEndpoint.accept(target.id)
        )
        if proposal?.id == target.id {
            proposal = nil
        }
        try await syncBlocks(response.blocks)
        await loadBlocks()
    }

    func reject(_ target: ScheduleProposal) async {
        errorMessage = nil
        do {
            _ = try await client.request(ScheduleEndpoint.reject(target.id)) as RecommendationResponse
        } catch {
            errorMessage = error.localizedDescription
        }
        if proposal?.id == target.id {
            proposal = nil
        }
    }

    func updateBlockTime(_ block: CalendarBlock, start: Date, end: Date) async throws {
        if !connectivity.isConnected, let store {
            let local = CalendarBlock(
                id: block.id,
                userId: block.userId,
                taskId: block.taskId,
                calendarEventId: block.calendarEventId,
                title: block.title,
                startAt: start,
                endAt: end,
                createdAt: block.createdAt,
                updatedAt: Date()
            )
            store.upsert(local, dirty: true)
            if let index = blocks.firstIndex(where: { $0.id == block.id }) {
                blocks[index] = local
            }
            return
        }

        let request = CalendarBlockUpdateRequest(startAt: start, endAt: end)
        let updated: CalendarBlock = try await client.request(
            CalendarEndpoint.updateBlock(id: block.id, request: request)
        )
        store?.upsert(updated)
        if let eventId = block.calendarEventId {
            do {
                try calendarService.updateTaskBlock(
                    eventIdentifier: eventId,
                    start: start,
                    end: end
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        if let index = blocks.firstIndex(where: { $0.id == updated.id }) {
            blocks[index] = updated
        }
    }

    func deleteBlock(_ block: CalendarBlock) async throws {
        if !connectivity.isConnected, let store {
            store.markDeleted(blockId: block.id)
        } else {
            do {
                _ = try await client.request(CalendarEndpoint.deleteBlock(block.id)) as MessageResponse
                store?.purgeBlock(id: block.id)
            } catch {
                if let store, isNetworkUnavailable(error) {
                    store.markDeleted(blockId: block.id)
                } else {
                    throw error
                }
            }
        }
        if let eventId = block.calendarEventId {
            try? calendarService.deleteTaskBlock(eventIdentifier: eventId)
        }
        blocks.removeAll { $0.id == block.id }
    }

    private func syncBlocks(_ newBlocks: [CalendarBlock]) async throws {
        if await calendarService.requestPermission() != .granted {
            blocks = newBlocks
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        for block in newBlocks {
            if let eventId = block.calendarEventId {
                try? calendarService.updateTaskBlock(
                    eventIdentifier: eventId,
                    title: block.title,
                    start: block.startAt,
                    end: block.endAt
                )
            } else {
                let eventId = try calendarService.createTaskBlock(
                    title: block.title,
                    start: block.startAt,
                    end: block.endAt
                )
                let request = CalendarBlockUpdateRequest(calendarEventId: eventId)
                _ = try await client.request(
                    CalendarEndpoint.updateBlock(id: block.id, request: request)
                ) as CalendarBlock
            }
        }
    }
}
