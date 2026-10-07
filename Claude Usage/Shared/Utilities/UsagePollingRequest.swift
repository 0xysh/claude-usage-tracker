import Foundation

/// Requests for passive usage polling. Credentials never go to configured proxies.
enum UsagePollingRequest {
    enum EndpointError: Error { case untrustedDestination }

    static func claudeOAuth(accessToken: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("claude-code/2.1.5", forHTTPHeaderField: "User-Agent")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        return request
    }

    static func codexURL(baseURL: String) throws -> URL {
        guard var components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              ["chatgpt.com", "chat.openai.com"].contains(host),
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil,
              ["", "/", "/backend-api", "/backend-api/"].contains(components.path) else {
            throw EndpointError.untrustedDestination
        }
        components.scheme = "https"
        components.host = host
        components.path = "/backend-api/wham/usage"
        guard let url = components.url else { throw EndpointError.untrustedDestination }
        return url
    }

    static func codex(baseURL: String, accessToken: String, accountID: String?) throws -> URLRequest {
        var request = URLRequest(url: try codexURL(baseURL: baseURL),
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        return request
    }
}

/// Refuse redirects for credential-bearing polling rather than trusting a new target.
final class UsagePollingSessionDelegate: NSObject, URLSessionTaskDelegate {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                               willPerformHTTPRedirection response: HTTPURLResponse,
                               newRequest request: URLRequest,
                               completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration, delegate: UsagePollingSessionDelegate(), delegateQueue: nil)
    }()
}
