# Calendar wing

Calendar is viable as an optional wing in Margin. It should be a separate calendar item, not a saved note: events have dates, recurrence, account permissions, and external ownership that notes do not.

When enabled in Settings, show a dedicated calendar wing that can be dragged anywhere among the notes. Clicking it opens a movable, resizable full-month calendar in a Margin window, with month navigation, event previews, and a link to open Calendar. Keep a useful empty state for no events and a reconnect state when permission is revoked.

Use Apple's EventKit to access calendars configured in macOS. Users add iCloud, Google, Exchange, or supported CalDAV accounts through macOS Calendar / Internet Accounts. Margin requests calendar access only after the feature is enabled. For macOS 14 and later, use full event access; retain the appropriate older access request for macOS 13.

Refetch the displayed date range when EventKit reports a store change and when the calendar window opens. The system handles provider synchronization. Show the last refresh and allow refresh, but do not promise instant cloud sync: refresh cadence, network availability, and provider behavior are outside Margin's control.

Create, edit, and delete events through EventKit. Changes to recurring events apply to the selected occurrence. Leave invitations and attendee responses to Calendar. Direct provider sign-in inside Margin would require additional authentication, token management, and provider-specific sync work; it is not needed because macOS already manages connected accounts.

Implemented: Settings → Calendar enables the wing, chooses its color and position, manages access, selects multiple connected calendars to display, and chooses a primary calendar for new events. The calendar indicator is hidden from the collapsed capsule. Clicking it opens a borderless, movable and resizable 680 × 590 42-day month grid styled like Margin, with weekday headings, date cells, event previews, month navigation, permission states, and Open in Calendar. New Event and each day's Add event action save to a writable EventKit calendar. Clicking a writable event opens an editor with its destination calendar and a confirmed Delete action. macOS manages provider synchronization. No permission is requested until the user chooses Allow Access. Live provider synchronization requires user-granted permission and a configured macOS Calendar account; it cannot be validated by offline self-checks.

Sources checked September 7, 2026:

- [Apple: calendar accounts on Mac](https://support.apple.com/en-ie/guide/calendar/icl4308d6701/mac)
- [Google: add Google Calendar to Apple Calendar](https://support.google.com/calendar/answer/99358)
- [Apple: accessing the EventKit store](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)
- [Apple: refresh after EventKit notifications](https://developer.apple.com/documentation/eventkit/updating-with-notifications)
