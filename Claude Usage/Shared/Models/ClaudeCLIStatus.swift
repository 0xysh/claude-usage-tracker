import Foundation
import CoreFoundation

/// Classifies a saved CLI snapshot without accessing a login file, Keychain,
/// system credential service or provider. Readiness is strictly local.
enum ClaudeCLIStatus: Equatable {
    case notSaved
    case incomplete
    case expired
    case ready
    case expiryUnknown

    var isReadyLocally: Bool { self == .ready }

    static func resolve(credentialsJSON: String?, now: Date = Date()) -> Self {
        guard let credentialsJSON else { return .notSaved }
        guard let data = credentialsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .incomplete }
        guard let rawExpiry = oauth["expiresAt"], !(rawExpiry is NSNull) else { return .expiryUnknown }
        guard let expiry = rawExpiry as? NSNumber,
              CFGetTypeID(expiry) != CFBooleanGetTypeID(),
              expiry.doubleValue.isFinite, expiry.doubleValue >= 0 else { return .incomplete }
        // Claude Code stores milliseconds; retain existing seconds compatibility.
        let seconds = expiry.doubleValue > 1e12 ? expiry.doubleValue / 1000 : expiry.doubleValue
        return seconds <= now.timeIntervalSince1970 ? .expired : .ready
    }

    var title: String {
        switch self {
        case .notSaved: return "No saved CLI login"
        case .incomplete: return "Saved login incomplete"
        case .expired: return "Login expired"
        case .ready: return "Credentials ready locally"
        case .expiryUnknown: return "Token expiry unavailable"
        }
    }

    var detail: String {
        switch self {
        case .notSaved: return "Sign in through Claude Code, then sync this account."
        case .incomplete: return "Saved CLI credentials do not contain a usable token and expiry. Sign in through Claude Code, then resync."
        case .expired: return "Sign in through Claude Code again, then resync this account."
        case .ready: return "The saved token has not expired. Refresh usage to verify the provider connection."
        case .expiryUnknown: return "The saved token has no expiry information. Refresh usage to verify the provider connection."
        }
    }
}
