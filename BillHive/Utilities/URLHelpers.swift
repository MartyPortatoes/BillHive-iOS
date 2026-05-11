import Foundation

// MARK: - URL Sanitization

/// Returns `url` only if it parses cleanly and uses the `https` scheme.
/// User-entered or imported URLs may otherwise contain `tel:`, `sms:`, `file:`,
/// or arbitrary app-scheme URLs that would route to whatever handler the user
/// has installed — turning a "Pay" button into a deep-link injection vector.
func bhSafeWebURL(_ raw: String) -> URL? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let url = URL(string: trimmed),
          let scheme = url.scheme?.lowercased(),
          scheme == "https" else { return nil }
    return url
}

/// Percent-encodes a single URL path or query component. Used to keep
/// user-entered Venmo handles and CashApp tags from injecting `&` / `?` / `#`
/// into deep-link URLs we construct.
func bhEncodeURLComponent(_ s: String) -> String {
    s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
}
