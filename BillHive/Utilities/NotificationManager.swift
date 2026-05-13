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

    /// How many days before the due date to send the reminder. Persisted in UserDefaults.
    @Published var reminderDaysBefore: Int {
        didSet {
            UserDefaults.standard.set(reminderDaysBefore, forKey: "reminderDaysBefore")
        }
    }

    static let dayOptions = [0, 1, 2, 3, 5, 7]

    /// Authorization status for notifications.
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private init() {
        dueDateRemindersEnabled = UserDefaults.standard.bool(forKey: "dueDateRemindersEnabled")
        let stored = UserDefaults.standard.object(forKey: "reminderDaysBefore") as? Int
        reminderDaysBefore = stored ?? 1
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

    private func scheduleReminder(bill: Bill, dueDay: Int, month: Int, year: Int, idSuffix: String) {
        let cal = Calendar.current

        var dueComps = DateComponents()
        dueComps.year = year
        dueComps.month = month
        dueComps.day = dueDay

        guard let dueDate = cal.date(from: dueComps) else { return }

        guard let reminderDate = cal.date(byAdding: .day, value: -reminderDaysBefore, to: dueDate) else { return }

        if reminderDate < Date() { return }

        var triggerComps = cal.dateComponents([.year, .month, .day], from: reminderDate)
        triggerComps.hour = 9
        triggerComps.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)

        let content = UNMutableNotificationContent()
        let dayLabel = bill.dueDayLabel ?? "\(dueDay)"
        if reminderDaysBefore == 0 {
            content.title = "\(bill.icon) \(bill.name) due today"
            content.body = "Your \(bill.name) bill is due today (the \(dayLabel))."
        } else if reminderDaysBefore == 1 {
            content.title = "\(bill.icon) \(bill.name) due tomorrow"
            content.body = "Your \(bill.name) bill is due on the \(dayLabel)."
        } else {
            content.title = "\(bill.icon) \(bill.name) due in \(reminderDaysBefore) days"
            content.body = "Your \(bill.name) bill is due on the \(dayLabel)."
        }
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
