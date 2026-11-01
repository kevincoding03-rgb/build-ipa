//  Look4Sat iOS port — calendar + local notification services
//  Re-implements the Android EventReminder/calendar pass-reminder flow
//  with EventKit + UserNotifications.  License: GPL-3.0
import EventKit
import UserNotifications
import Look4SatCore

/// Adds upcoming satellite passes to the user's calendar as events.
final class CalendarService {
    private let store = EKEventStore()

    /// Request write access and add events for each pass.
    @MainActor
    func addPasses(_ passes: [OrbitalPass]) async -> Bool {
        guard try? await store.requestAccess(to: .event) == true else { return false }
        guard let cal = store.defaultCalendarForNewEvents() else { return false }
        for pass in passes {
            let event = EKEvent(eventStore: store)
            event.calendar = cal
            event.title = "Pass: \(pass.name)"
            event.startDate = Date(timeIntervalSince1970: Double(pass.aosTime) / 1000)
            event.endDate = Date(timeIntervalSince1970: Double(pass.losTime) / 1000)
            event.notes = String(format:
                "AOS az %.0f° · LOS az %.0f° · max elev %.0f°",
                pass.aosAzimuth, pass.losAzimuth, pass.maxElevation)
            try? store.save(event, span: .thisEvent)
        }
        return true
    }
}

/// Local notifications when a pass is about to start (AOS − lead time).
final class NotificationService {
    /// Request auth and schedule AOS reminders.
    @MainActor
    func schedule(passes: [OrbitalPass], leadSeconds: Int = 300) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            let granted = try? await center.requestAuthorization(options: [.alert, .sound]) == true
            guard granted == true else { return false }
        }
        for pass in passes {
            let start = Date(timeIntervalSince1970: Double(pass.aosTime) / 1000)
            let content = UNMutableNotificationContent()
            content.title = "Pass starting: \(pass.name)"
            content.body = String(format: "Max elevation %.0f°. LOS at %@.",
                                 pass.maxElevation,
                                 Date(timeIntervalSince1970: Double(pass.losTime) / 1000)
                                     .formatted(date: .omitted, time: .standard))
            let leadMs = Int64(leadSeconds) * 1000
            let fireInterval = max(Double(pass.aosTime - Int64(Date().timeIntervalSince1970 * 1000) - leadMs) / 1000.0, 0)
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: fireInterval, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "l4s-\(pass.catNum)",
                                                          content: content, trigger: trigger))
        }
        return true
    }
}
