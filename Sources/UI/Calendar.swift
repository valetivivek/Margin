import AppKit
import SwiftUI
import EventKit
import Combine

// This item is a deck presentation only; it is never stored or exported as a note.
enum CalendarWing {
    static let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static func item(color: NoteColor) -> Note {
        Note(id: id, title: "Calendar", body: "Your schedule\nClick to open the full month", color: color, presentation: NotePresentation(icon: "calendar"))
    }

    static func items(notes: [Note], enabled: Bool, position: Int, limit: Int, color: NoteColor = .sky) -> [Note] {
        guard enabled else { return Array(notes.prefix(limit)) }
        let visible = Array(notes.prefix(max(0, limit - 1)))
        var items = visible
        items.insert(item(color: color), at: min(max(0, position), visible.count))
        return items
    }

    static func movedPosition(_ position: Int, by step: Int, noteCount: Int, limit: Int) -> Int {
        let maximum = min(noteCount, max(0, limit - 1))
        let current = min(max(0, position), maximum)
        let (moved, overflow) = current.addingReportingOverflow(step)
        return overflow ? (step > 0 ? maximum : 0) : min(max(0, moved), maximum)
    }
}

final class CalendarAgenda: ObservableObject {
    private let store = EKEventStore()
    @Published var date = Date()
    @Published var calendarIDs: [String]
    @Published private(set) var calendars: [EKCalendar] = []
    @Published private(set) var events: [EKEvent] = []
    @Published private(set) var authorized = false
    @Published private(set) var requesting = false
    @Published private(set) var message = "Allow calendar access to see your schedule."
    @Published private(set) var refreshed: Date?
    private var observations = Set<AnyCancellable>()

    init(calendarIDs: [String] = []) {
        self.calendarIDs = calendarIDs
        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)
            .merge(with: NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }.store(in: &observations)
    }

    var writableCalendars: [EKCalendar] { calendars.filter(\.allowsContentModifications) }

    static func eventDates(start: Date, end: Date, allDay: Bool, calendar: Calendar = .current) -> (Date, Date)? {
        if allDay {
            let day = calendar.startOfDay(for: start)
            return (day, calendar.date(byAdding: .day, value: 1, to: day)!)
        }
        return end > start ? (start, end) : nil
    }

    static func visibleCalendarIDs(current: [String], saved: String) -> [String] {
        current.isEmpty || current.contains(saved) ? current : current + [saved]
    }

    func saveEvent(_ existing: EKEvent? = nil, title: String, start: Date, end: Date, allDay: Bool, calendarID: String) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let dates = Self.eventDates(start: start, end: end, allDay: allDay) else {
            throw NSError(domain: "Margin.Calendar", code: 1, userInfo: [NSLocalizedDescriptionKey: "Add a title and make sure the end is after the start."])
        }
        let selected = writableCalendars.first { $0.calendarIdentifier == calendarID }
            ?? store.defaultCalendarForNewEvents
            ?? writableCalendars.first
        guard let selected, selected.allowsContentModifications else {
            throw NSError(domain: "Margin.Calendar", code: 2, userInfo: [NSLocalizedDescriptionKey: "No writable calendar is available. Add one in macOS Calendar first."])
        }
        let event = existing ?? EKEvent(eventStore: store)
        event.title = title; event.startDate = dates.0; event.endDate = dates.1
        event.isAllDay = allDay; event.calendar = selected
        try store.save(event, span: .thisEvent, commit: true)
        calendarIDs = Self.visibleCalendarIDs(current: calendarIDs, saved: selected.calendarIdentifier)
        refresh()
    }

    func deleteEvent(_ event: EKEvent) throws {
        guard event.calendar.allowsContentModifications else {
            throw NSError(domain: "Margin.Calendar", code: 3, userInfo: [NSLocalizedDescriptionKey: "This calendar does not allow changes."])
        }
        try store.remove(event, span: .thisEvent, commit: true)
        refresh()
    }

    func requestAccess() {
        guard !requesting else { return }
        requesting = true
        let completion: (Bool, Error?) -> Void = { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.requesting = false
                self.refresh()
                if let error { self.message = error.localizedDescription }
            }
        }
        if #available(macOS 14, *) { store.requestFullAccessToEvents(completion: completion) }
        else { store.requestAccess(to: .event, completion: completion) }
    }

    static func dayRange(_ date: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start)!)
    }

    static func monthDays(_ date: Date, calendar: Calendar = .current) -> [Date] {
        let start = calendar.dateInterval(of: .month, for: date)!.start
        let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let first = calendar.date(byAdding: .day, value: -offset, to: start)!
        return (0..<42).map { calendar.date(byAdding: .day, value: $0, to: first)! }
    }

    func events(on date: Date) -> [EKEvent] {
        let range = Self.dayRange(date)
        return events.filter { $0.startDate < range.end && $0.endDate > range.start }
    }

    func refresh() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14, *) { authorized = status == .fullAccess }
        else { authorized = status == .authorized }
        guard authorized else {
            events = []; calendars = []; refreshed = nil
            message = status == .notDetermined ? "Allow calendar access to see your schedule." : "Calendar access is off. Allow Margin in System Settings → Privacy & Security → Calendars."
            return
        }
        calendars = store.calendars(for: .event).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let available = Set(calendars.map(\.calendarIdentifier))
        calendarIDs = calendarIDs.filter(available.contains)
        let days = Self.monthDays(date)
        let range = DateInterval(start: days[0], end: Self.dayRange(days[41]).end)
        let selected = calendarIDs.isEmpty ? calendars : calendars.filter { calendarIDs.contains($0.calendarIdentifier) }
        events = selected.isEmpty ? [] : store.events(matching: store.predicateForEvents(withStart: range.start, end: range.end, calendars: selected))
            .sorted { a, b in a.isAllDay != b.isAllDay ? a.isAllDay : a.startDate < b.startDate }
        refreshed = Date()
    }

    static func openCalendar() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

struct CalendarAgendaView: View {
    @ObservedObject var settings: AppSettings
    @StateObject private var agenda: CalendarAgenda
    @State private var selectedDay: Date?
    @State private var eventDraft: CalendarEventDraft?
    @State private var closeHovered = false
    let close: () -> Void
    let openSettings: () -> Void
    private var calendar: Calendar { .current }
    private var accent: Color { Color(nsColor: settings.interfaceColor.nsColor(isDark: false)) }
    private var selectedCalendarName: String {
        if agenda.calendarIDs.isEmpty { return "All calendars" }
        if agenda.calendarIDs.count == 1 {
            return agenda.calendars.first { $0.calendarIdentifier == agenda.calendarIDs[0] }?.title ?? "Selected calendar"
        }
        return "\(agenda.calendarIDs.count) calendars"
    }

    init(settings: AppSettings, close: @escaping () -> Void = {}, openSettings: @escaping () -> Void = {}) {
        self.settings = settings; self.close = close; self.openSettings = openSettings
        _agenda = StateObject(wrappedValue: CalendarAgenda(calendarIDs: settings.calendarVisibleIDs))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: close) {
                    HStack(spacing: 7) {
                        Circle().fill(closeHovered ? Color(nsColor: .systemRed) : .black.opacity(0.30)).frame(width: 12, height: 12)
                        Circle().fill(.black.opacity(0.12)).frame(width: 12, height: 12)
                    }.frame(width: 34, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain).onHover { closeHovered = $0 }
                .accessibilityLabel("Close calendar")
                Image(systemName: "calendar").font(.system(size: 15, weight: .semibold)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(agenda.date.formatted(.dateTime.month(.wide).year())).font(SettingsPalette.font(20, medium: true))
                    Text(selectedCalendarName).font(SettingsPalette.font(10)).foregroundStyle(.black.opacity(0.48))
                }
                Spacer()
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous month")
                Button("Today") { agenda.date = Date() }
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next month")
                Button { eventDraft = CalendarEventDraft(date: Date()) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New event").disabled(!agenda.authorized || agenda.writableCalendars.isEmpty)
                DragHandle(accessibilityLabel: "Move calendar").frame(width: 34, height: 30).help("Drag to move the calendar anywhere")
            }
            .buttonStyle(CalendarControlStyle()).padding(.horizontal, 18).frame(height: 58)
            Divider().opacity(0.18).padding(.horizontal, 18)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(0..<7) { index in
                        Text(calendar.shortWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7].uppercased())
                            .font(SettingsPalette.font(10, medium: true)).foregroundStyle(.black.opacity(0.48))
                            .frame(maxWidth: .infinity).frame(height: 28)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                    ForEach(CalendarAgenda.monthDays(agenda.date), id: \.self) { day in dayCell(day) }
                }
            }
            .background(.white.opacity(0.24), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.34)))
            .overlay {
                if !agenda.authorized {
                    VStack(spacing: 10) {
                        Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 24)).foregroundStyle(accent)
                        Text("Calendar access is managed in Settings").font(SettingsPalette.font(14, medium: true))
                        Text(agenda.message).font(SettingsPalette.font(11)).foregroundStyle(.black.opacity(0.55)).multilineTextAlignment(.center).frame(maxWidth: 320)
                        Button("Open Calendar Settings", action: openSettings).buttonStyle(CalendarControlStyle())
                    }
                    .padding(22).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(.horizontal, 18).padding(.top, 12)
            Spacer(minLength: 10)
            HStack(spacing: 12) {
                Text(agenda.refreshed.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Events sync through macOS Calendar")
                    .font(SettingsPalette.font(10)).foregroundStyle(.black.opacity(0.45))
                Spacer()
                Button("New Event") { eventDraft = CalendarEventDraft(date: Date()) }
                    .disabled(!agenda.authorized || agenda.writableCalendars.isEmpty)
                Button("Calendar Settings", action: openSettings)
                Button("Open in Calendar", action: CalendarAgenda.openCalendar)
                if agenda.authorized {
                    Button { agenda.refresh() } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Refresh calendar")
                }
            }
            .buttonStyle(CalendarControlStyle()).padding(.horizontal, 18).frame(height: 52)
        }
        .frame(minWidth: 620, minHeight: 540)
        .foregroundStyle(.black.opacity(0.76)).background(settings.calendarColor.color)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .environment(\.colorScheme, .light)
        .onAppear { agenda.calendarIDs = settings.calendarVisibleIDs; agenda.refresh() }
        .onChange(of: agenda.date) { _ in agenda.refresh() }
        .onChange(of: settings.calendarVisibleIDs) { value in agenda.calendarIDs = value; agenda.refresh() }
        .onChange(of: agenda.calendarIDs) { value in if settings.calendarVisibleIDs != value { settings.calendarVisibleIDs = value } }
        .sheet(item: $eventDraft) { draft in
            CalendarEventComposer(agenda: agenda, date: draft.date, event: draft.event, preferredCalendarID: settings.calendarID,
                                  color: settings.calendarColor.color)
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let events = agenda.events(on: day)
        let inMonth = calendar.isDate(day, equalTo: agenda.date, toGranularity: .month)
        return Button { selectedDay = day } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(calendar.component(.day, from: day))")
                    .font(SettingsPalette.font(12, medium: calendar.isDateInToday(day)))
                    .foregroundStyle(calendar.isDateInToday(day) ? Color.white : .black.opacity(0.72))
                    .frame(width: 23, height: 23)
                    .background(calendar.isDateInToday(day) ? accent : .clear, in: Circle())
                ForEach(Array(events.prefix(2).enumerated()), id: \.offset) { _, event in
                    HStack(spacing: 4) {
                        Circle().fill(eventColor(event)).frame(width: 5, height: 5)
                        Text(event.title ?? "Event").font(SettingsPalette.font(9, medium: true)).lineLimit(1)
                    }
                    .padding(.horizontal, 5).frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
                    .background(eventColor(event).opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
                }
                if events.count > 2 { Text("+\(events.count - 2) more").font(SettingsPalette.font(8)).foregroundStyle(.black.opacity(0.48)) }
                Spacer(minLength: 0)
            }
            .padding(6).frame(maxWidth: .infinity, alignment: .topLeading).frame(height: 66)
            .background(calendar.isDateInToday(day) ? accent.opacity(0.07) : .clear)
            .opacity(inMonth ? 1 : 0.34)
            .overlay(Rectangle().stroke(.black.opacity(0.09), lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(events.count) events")
        .popover(isPresented: Binding(get: { selectedDay == day }, set: { if !$0 { selectedDay = nil } })) {
            VStack(alignment: .leading, spacing: 12) {
                Text(day.formatted(date: .complete, time: .omitted)).font(SettingsPalette.font(15, medium: true))
                if events.isEmpty { Text("No events").foregroundStyle(.secondary) }
                else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                                Button {
                                    selectedDay = nil
                                    DispatchQueue.main.async { eventDraft = CalendarEventDraft(date: event.startDate, event: event) }
                                } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(event.title ?? "Untitled event").font(SettingsPalette.font(13, medium: true))
                                            Text(event.isAllDay ? "All day" : "\(event.startDate.formatted(date: .omitted, time: .shortened)) – \(event.endDate.formatted(date: .omitted, time: .shortened))").font(SettingsPalette.font(11))
                                            if let location = event.location, !location.isEmpty { Text(location).font(SettingsPalette.font(11)).foregroundStyle(.secondary) }
                                            Text(event.calendar.title).font(SettingsPalette.font(10)).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if event.calendar.allowsContentModifications { Image(systemName: "pencil").foregroundStyle(.secondary) }
                                    }.contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).disabled(!event.calendar.allowsContentModifications)
                                .help(event.calendar.allowsContentModifications ? "Edit event" : "This calendar is read-only")
                            }
                        }
                    }.frame(maxHeight: 280)
                }
            }.padding(16).frame(width: 300)
                .safeAreaInset(edge: .bottom) {
                    Button { selectedDay = nil; DispatchQueue.main.async { eventDraft = CalendarEventDraft(date: day) } } label: {
                        Label("Add event", systemImage: "plus")
                    }
                    .buttonStyle(CalendarControlStyle()).disabled(!agenda.authorized || agenda.writableCalendars.isEmpty)
                    .padding(.bottom, 10)
                }
        }
    }

    private func eventColor(_ event: EKEvent) -> Color { Color(nsColor: NSColor(cgColor: event.calendar.cgColor) ?? .systemBlue) }
    private func moveMonth(_ value: Int) { agenda.date = calendar.date(byAdding: .month, value: value, to: calendar.dateInterval(of: .month, for: agenda.date)!.start) ?? agenda.date }
}

private struct CalendarEventDraft: Identifiable {
    let id = UUID()
    let date: Date
    let event: EKEvent?

    init(date: Date, event: EKEvent? = nil) { self.date = date; self.event = event }
}

private struct CalendarEventComposer: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var agenda: CalendarAgenda
    let event: EKEvent?
    let color: Color
    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @State private var allDay: Bool
    @State private var calendarID: String
    @State private var error: String?
    @State private var confirmingDelete = false

    init(agenda: CalendarAgenda, date: Date, event: EKEvent? = nil, preferredCalendarID: String, color: Color) {
        self.agenda = agenda; self.event = event; self.color = color
        let calendar = Calendar.current
        let start = event?.startDate ?? calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
        _title = State(initialValue: event?.title ?? "")
        _start = State(initialValue: start); _end = State(initialValue: event?.endDate ?? start.addingTimeInterval(3600))
        _allDay = State(initialValue: event?.isAllDay ?? false)
        let requested = event?.calendar.calendarIdentifier ?? preferredCalendarID
        let preferred = agenda.writableCalendars.contains { $0.calendarIdentifier == requested }
            ? requested : agenda.writableCalendars.first?.calendarIdentifier ?? ""
        _calendarID = State(initialValue: preferred)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: event == nil ? "calendar.badge.plus" : "calendar.badge.clock").font(.system(size: 18, weight: .semibold))
                Text(event == nil ? "New event" : "Edit event").font(SettingsPalette.font(20, medium: true))
                Spacer()
            }
            TextField("Event title", text: $title).textFieldStyle(.roundedBorder)
            Toggle("All-day event", isOn: $allDay)
            DatePicker("Starts", selection: $start, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
            DatePicker("Ends", selection: $end, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
            Picker(event == nil ? "Save to" : "Sync changes to", selection: $calendarID) {
                ForEach(agenda.writableCalendars, id: \.calendarIdentifier) { calendar in
                    Text("\(calendar.title) · \(calendar.source.title)").tag(calendar.calendarIdentifier)
                }
            }
            if let error { Text(error).font(SettingsPalette.font(11)).foregroundStyle(.red) }
            HStack {
                if event != nil { Button("Delete", role: .destructive) { confirmingDelete = true }.foregroundStyle(.red) }
                Spacer()
                Button("Cancel") { dismiss() }
                Button(event == nil ? "Add Event" : "Save Changes") {
                    do { try agenda.saveEvent(event, title: title, start: start, end: end, allDay: allDay, calendarID: calendarID); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || calendarID.isEmpty || (!allDay && end <= start))
            }
        }
        .font(SettingsPalette.font(13)).foregroundStyle(.black.opacity(0.76))
        .padding(22).frame(width: 430).background(color)
        .environment(\.colorScheme, .light)
        .confirmationDialog("Delete this event?", isPresented: $confirmingDelete) {
            Button("Delete Event", role: .destructive) {
                guard let event else { return }
                do { try agenda.deleteEvent(event); dismiss() }
                catch { self.error = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes the event from its connected calendar account.") }
    }
}

private struct CalendarControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(SettingsPalette.font(11, medium: true)).padding(.horizontal, 10).frame(height: 28)
            .background(.black.opacity(configuration.isPressed ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
