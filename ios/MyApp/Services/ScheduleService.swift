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

    init(client: APIClient? = nil, calendarService: CalendarService? = nil) {
        self.client = client ?? APIClient()
        self.calendarService = calendarService ?? CalendarService()
    }

    func loadBlocks() async {
        do {
            let response: CalendarBlockListResponse = try await client.request(
                CalendarEndpoint.listBlocks
            )
            blocks = response.items.sorted { $0.startAt < $1.startAt }
        } catch {
            errorMessage = error.localizedDescription
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
        let request = CalendarBlockUpdateRequest(startAt: start, endAt: end)
        let updated: CalendarBlock = try await client.request(
            CalendarEndpoint.updateBlock(id: block.id, request: request)
        )
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
        _ = try await client.request(CalendarEndpoint.deleteBlock(block.id)) as MessageResponse
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
