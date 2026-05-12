import Foundation
import UserNotifications

// MARK: - Notification Manager

/// Manages local notifications for bill due date reminders.
///
/// Schedules a notification the day before each bill's due date for the
/// current and next month. Notifications are rescheduled whenever bills
/// change or when the user toggles the feature.
@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    /// Whether due date reminders are enabled. Persisted in UserDefaults.
    @Published var dueDateRemindersEnabled: Bool {
        didSet {
            UserDefaults.standard.set(dueDateRemindersEnabled, forKey: "dueDateRemindersEnabled")
        }
    }

    /// Authorization status for notifications.
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private init() {
        dueDateRemindersEnabled = UserDefaults.standard.bool(forKey: "dueDateRemindersEnabled")
    }

    // MARK: - Authorization

    /// Requests notification permission if not already determined.
    /// Returns true if authorized.
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            let settings = await center.notificationSettings()
            authorizationStatus = settings.authorizationStatus
            return granted
        } catch {
            return false
        }
    }

    /// Refreshes the current authorization status without prompting.
    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    // MARK: - Scheduling

    /// Reschedules all due date notifications based on the current bills.
    ///
    /// Clears existing bill-related notifications, then schedules one
    /// notification per bill that has a `dueDay` set — fired at 9:00 AM
    /// the day before the due date.
    func reschedule(bills: [Bill]) {
        guard dueDateRemindersEnabled else {
            removeAllBillNotifications()
            return
        }

        let center = UNUserNotificationCenter.current()

        // Remove existing bill notifications
        center.removePendingNotificationRequests(withIdentifiers:
            bills.map { "bill_due_\($0.id)" } +
            bills.map { "bill_due_next_\($0.id)" }
        )

        let cal = Calendar.current
        let now = Date()
        let currentMonth = cal.component(.month, from: now)
        let currentYear = cal.component(.year, from: now)

        // Next month
        var nextMonth = currentMonth + 1
        var nextYear = currentYear
        if nextMonth > 12 { nextMonth = 1; nextYear += 1 }

        for bill in bills {
            guard let dueDay = bill.dueDay else { continue }

            // Schedule for current month (if the reminder day hasn't passed)
            scheduleReminder(
                bill: bill,
                dueDay: dueDay,
                month: currentMonth,
                year: currentYear,
                idSuffix: bill.id
            )

            // Schedule for next month
            scheduleReminder(
                bill: bill,
                dueDay: dueDay,
                month: nextMonth,
                year: nextYear,
                idSuffix: "next_\(bill.id)"
            )
        }
    }

    /// Schedules a single reminder notification the day before the bill is due.
    private func scheduleReminder(bill: Bill, dueDay: Int, month: Int, year: Int, idSuffix: String) {
        let cal = Calendar.current

        // Compute the reminder day (day before due date)
        var dueComps = DateComponents()
        dueComps.year = year
        dueComps.month = month
        dueComps.day = dueDay

        // Validate the date exists (e.g. Feb 31 doesn't exist)
        guard let dueDate = cal.date(from: dueComps) else { return }

        // Reminder fires at 9:00 AM the day before
        guard let reminderDate = cal.date(byAdding: .day, value: -1, to: dueDate) else { return }

        // Don't schedule if the reminder date is in the past
        if reminderDate < Date() { return }

        var triggerComps = cal.dateComponents([.year, .month, .day], from: reminderDate)
        triggerComps.hour = 9
        triggerComps.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)

        let content = UNMutableNotificationContent()
        content.title = "\(bill.icon) \(bill.name) due tomorrow"
        content.body = bill.dueDayLabel.map { "Your \(bill.name) bill is due on the \($0)." } ?? "Your \(bill.name) bill is due tomorrow."
        content.sound = .default
        content.categoryIdentifier = "BILL_DUE"

        let request = UNNotificationRequest(
            identifier: "bill_due_\(idSuffix)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[NotificationManager] Failed to schedule: \(error.localizedDescription)")
            }
        }
    }

    /// Removes all bill-related pending notifications.
    func removeAllBillNotifications() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let billIds = requests.filter { $0.identifier.hasPrefix("bill_due_") }.map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: billIds)
        }
    }

    // MARK: - Toggle

    /// Toggles due date reminders on/off, handling authorization if needed.
    func toggleReminders(bills: [Bill]) async {
        if !dueDateRemindersEnabled {
            // Turning on — request permission first
            let granted = await requestAuthorization()
            if granted {
                dueDateRemindersEnabled = true
                reschedule(bills: bills)
            }
        } else {
            // Turning off
            dueDateRemindersEnabled = false
            removeAllBillNotifications()
        }
    }
}
