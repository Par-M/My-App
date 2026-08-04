import SwiftUI

struct ScheduleProposalView: View {
    @Environment(ScheduleService.self) private var scheduleService
    @Environment(\.dismiss) private var dismiss

    @State private var errorDismissed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let message = scheduleService.proposal?.message {
                        Label(message, systemImage: "sparkles")
                            .font(.headline)
                    }

                    if let proposal = scheduleService.proposal {
                        if proposal.items.isEmpty {
                            ContentUnavailableView(
                                "Nothing to Schedule",
                                systemImage: "calendar.badge.exclamationmark",
                                description: Text(
                                    proposal.failureReason ?? "No tasks could be placed in this window."
                                )
                            )
                        } else {
                            ForEach(proposal.items) { item in
                                proposalItemRow(item)
                            }
                        }

                        if proposal.meta.overcommitted {
                            overcommitmentBanner(proposal.meta)
                        }

                        if let reasoning = proposal.reasoning, !reasoning.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("AI Reasoning")
                                    .font(.subheadline.bold())
                                Text(reasoning)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Proposed Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let proposal = scheduleService.proposal {
                    HStack(spacing: 12) {
                        Button {
                            Task { await reject(proposal) }
                        } label: {
                            Text("Reject")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(scheduleService.isSyncing)

                        Button {
                            Task { await accept(proposal) }
                        } label: {
                            if scheduleService.isSyncing {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Accept & Add to Calendar")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(scheduleService.isSyncing || proposal.items.isEmpty)
                    }
                    .padding()
                    .background(.bar)
                }
            }
        }
    }

    private func proposalItemRow(_ item: ScheduleItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.taskTitle)
                    .font(.headline)
                Spacer()
                Text(item.start.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(item.start.formatted(date: .omitted, time: .shortened)) – \(item.end.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !item.reason.isEmpty {
                Text(item.reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func overcommitmentBanner(_ meta: ScheduleMeta) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Not enough free time", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.orange)
            if let risk = meta.risk {
                Text(risk)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !meta.deferredTasks.isEmpty {
                Text("Deferred: \(meta.deferredTasks.joined(separator: ", "))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private func accept(_ proposal: ScheduleProposal) async {
        do {
            try await scheduleService.accept(proposal)
            dismiss()
        } catch {
            scheduleService.presentError(error.localizedDescription)
        }
    }

    private func reject(_ proposal: ScheduleProposal) async {
        await scheduleService.reject(proposal)
        dismiss()
    }
}

#Preview {
    ScheduleProposalView()
        .environment(ScheduleService())
}
