import SwiftUI
import MessageUI

struct MailComposeView: UIViewControllerRepresentable {
    let request: MailComposeRequest
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([request.to])
        vc.setSubject(request.subject)
        vc.setMessageBody(request.body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            dismiss()
        }
    }
}

struct MailFallbackView: View {
    let request: MailComposeRequest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.bhBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("No Mail Account")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.bhText)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.bhAmber)
                }

                Text("Mail app is not configured. Copy the email body below and paste it manually.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.bhMuted)

                ScrollView {
                    Text(request.body)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.bhText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.bhSurface2)
                        .cornerRadius(8)
                }

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
