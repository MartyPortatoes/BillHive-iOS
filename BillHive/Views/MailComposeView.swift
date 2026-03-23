import SwiftUI
import MessageUI

// MARK: - Mail Compose View

/// UIKit wrapper that presents the system `MFMailComposeViewController`
/// for sending a pre-filled email (recipient, subject, body).
///
/// Used by the BillHive (local/iCloud) target when the user taps
/// "Send Email" for a household member. Dismissed automatically when
/// the user sends, saves, or cancels.
struct MailComposeView: UIViewControllerRepresentable {
    /// The email configuration containing recipient, subject, and body.
    let request: MailComposeRequest

    /// Environment action used to dismiss this view.
    @Environment(\.dismiss) private var dismiss

    /// Creates a coordinator to handle the mail compose delegate callbacks.
    ///
    /// - Returns: A new `Coordinator` instance.
    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    /// Creates and configures the `MFMailComposeViewController`.
    ///
    /// - Parameter context: The representable context containing the coordinator.
    /// - Returns: A configured mail compose view controller with pre-filled email details.
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([request.to])
        vc.setSubject(request.subject)
        vc.setMessageBody(request.body, isHTML: false)
        return vc
    }

    /// Updates the view controller when the representable state changes.
    ///
    /// This implementation performs no updates as the mail compose controller
    /// is typically dismissed immediately after sending or canceling.
    ///
    /// - Parameters:
    ///   - uiViewController: The mail compose controller to update.
    ///   - context: The representable context.
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    // MARK: - Coordinator

    /// Coordinator that handles the `MFMailComposeViewControllerDelegate`
    /// callback and dismisses the sheet.
    ///
    /// This class implements the delegate protocol to respond to mail compose events
    /// such as sending, saving, or canceling the email.
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        /// The dismiss action used to close the mail compose view.
        let dismiss: DismissAction

        /// Initializes the coordinator with a dismiss action.
        ///
        /// - Parameter dismiss: The dismiss action to call when the mail compose
        ///   controller finishes.
        init(dismiss: DismissAction) { self.dismiss = dismiss }

        /// Handles the completion of the mail compose operation.
        ///
        /// Dismisses the mail compose view regardless of whether the user sent,
        /// saved, or canceled the email.
        ///
        /// - Parameters:
        ///   - controller: The mail compose view controller.
        ///   - result: The result of the compose operation.
        ///   - error: An optional error if the operation failed.
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            dismiss()
        }
    }
}

// MARK: - Mail Fallback View

/// Fallback screen shown when the device has no configured Mail account.
///
/// When the system Mail app is not available or configured, this view displays
/// the email body as copiable text. Users can then paste the email body into
/// their preferred email client. Includes a "Copy to Clipboard" button for convenience.
struct MailFallbackView: View {
    /// The email configuration containing recipient, subject, and body.
    let request: MailComposeRequest

    /// Environment action used to dismiss this view.
    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    /// The view hierarchy displaying the fallback UI.
    ///
    /// Presents a title, explanation text, a scrollable text box with the email body,
    /// and a "Copy to Clipboard" button.
    var body: some View {
        ZStack {
            HexBGView().ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                // MARK: Header
                HStack {
                    Text("No Mail Account")
                        .font(.system(size: 18, weight: .bold, design: .default))
                        .foregroundColor(.bhText)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.bhAmber)
                }

                // MARK: Instructions
                Text("Mail app is not configured. Copy the email body below and paste it manually.")
                    .font(.system(size: 12, design: .default))
                    .foregroundColor(.bhMuted)

                // MARK: Email Body Display
                ScrollView {
                    Text(request.body)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.bhText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.bhSurface2)
                        .cornerRadius(8)
                }

                // MARK: Copy Button
                Button {
                    UIPasteboard.general.string = request.body
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Copy to Clipboard")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(BHPrimaryButtonStyle())

                Spacer()
            }
            .padding(20)
        }
    }
}
