import Foundation

/// Creates a reviewable GitHub issue draft using only the user's role and message.
/// It does not publish an issue, read credentials, or make a network request.
enum FeedbackIssueURL {
    // This conservative app limit is not a claim about GitHub's universal URL limit.
    static let maximumURLBytes = 7_000

    enum DraftError: Error {
        case emptyMessage
        case invalidRepository
        case tooLong
    }

    static func makeURL(repositoryURL: String, role: String, message: String) -> URL? {
        try? makeDraftURL(repositoryURL: repositoryURL, role: role, message: message).get()
    }

    static func makeDraftURL(repositoryURL: String, role: String, message: String) -> Result<URL, DraftError> {
        let draftMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draftMessage.isEmpty else { return .failure(.emptyMessage) }
        guard var components = URLComponents(string: repositoryURL),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "github.com",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil else { return .failure(.invalidRepository) }

        let segments = components.path.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.count == 3,
              segments[0].isEmpty,
              isRepositorySegment(segments[1]),
              isRepositorySegment(segments[2]) else { return .failure(.invalidRepository) }

        components.path += "/issues/new"
        components.queryItems = [
            URLQueryItem(name: "title", value: "App feedback"),
            URLQueryItem(name: "body", value: "Role: \(role)\n\n\(draftMessage)")
        ]
        // GitHub's query parser treats a literal '+' as a space. Encode it explicitly.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { return .failure(.invalidRepository) }
        guard url.absoluteString.utf8.count <= maximumURLBytes else { return .failure(.tooLong) }
        return .success(url)
    }

    private static func isRepositorySegment(_ segment: Substring) -> Bool {
        !segment.isEmpty && segment != "." && segment != ".." &&
        segment.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || "-_.".contains(character))
        }
    }
}
