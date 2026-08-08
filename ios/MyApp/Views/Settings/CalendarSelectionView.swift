import EventKit
import SwiftUI

struct CalendarSelectionView: View {
    @Environment(CalendarService.self) private var calendarService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(calendarService.availableCalendars, id: \.calendarIdentifier) { calendar in
                        Button {
                            calendarService.setCalendarSelected(
                                calendar,
                                selected: !calendarService.isSelected(calendar)
                            )
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(calendar.cgColor))
                                    .frame(width: 12, height: 12)
                                Text(calendar.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if calendarService.isSelected(calendar) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Only the selected calendars are used to find free time when scheduling.")
                }
            }
            .navigationTitle("Calendars to Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    CalendarSelectionView()
        .environment(CalendarService())
}
