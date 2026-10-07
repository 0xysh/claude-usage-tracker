import XCTest
@testable import Claude_Usage

final class FeedbackIssueURLTests: XCTestCase {
    private let repositoryURL = "https://github.com/0xysh/claude-usage-tracker"

    func testDraftTargetsConfiguredForkWithoutPublishing() throws {
        let url = try XCTUnwrap(FeedbackIssueURL.makeURL(
            repositoryURL: repositoryURL, role: "Developer", message: "Improve the usage display."
        ))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "github.com")
        XCTAssertEqual(components.path, "/0xysh/claude-usage-tracker/issues/new")
        XCTAssertNil(components.user)
        XCTAssertNil(components.password)
        XCTAssertNil(components.fragment)
        XCTAssertEqual(components.queryItems?.map(\.name), ["title", "body"])
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "title" })?.value, "App feedback")
    }

    func testUnicodeAndQueryCharactersRemainInsideDraftBody() throws {
        let message = "שלום + 50% &labels=security#details\nA \"quote\" and a URL: https://example.com/?x=1&y=2"
        let url = try XCTUnwrap(FeedbackIssueURL.makeURL(
            repositoryURL: repositoryURL, role: "Designer & researcher", message: message
        ))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.host, "github.com")
        XCTAssertEqual(components.path, "/0xysh/claude-usage-tracker/issues/new")
        XCTAssertEqual(components.queryItems?.count, 2)
        XCTAssertFalse(components.percentEncodedQuery?.contains("+") ?? true,
                       "literal plus must not become a space in GitHub's query parser")
        XCTAssertTrue(components.percentEncodedQuery?.contains("%2B") ?? false)
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "body" })?.value,
                       "Role: Designer & researcher\n\n" + message)
        XCTAssertNil(components.fragment)
    }

    func testOnlyExplicitRoleAndMessageAreIncluded() throws {
        let url = try XCTUnwrap(FeedbackIssueURL.makeURL(
            repositoryURL: repositoryURL, role: "Student", message: "  Add a local report.\n "
        ))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "body" })?.value,
                       "Role: Student\n\nAdd a local report.")
        XCTAssertFalse(url.absoluteString.contains("email"))
        XCTAssertFalse(url.absoluteString.contains("name="))
        XCTAssertFalse(url.absoluteString.contains("token"))
    }

    func testWhitespaceOnlyMessageDoesNotCreateDraft() {
        XCTAssertNil(FeedbackIssueURL.makeURL(
            repositoryURL: repositoryURL, role: "Developer", message: " \n\t "
        ))
    }

    func testRepositoryURLCannotRedirectDraftToUnexpectedDestination() {
        let invalidRepositories = [
            "http://github.com/0xysh/claude-usage-tracker",
            "https://github.com.evil.example/0xysh/claude-usage-tracker",
            "https://attacker@github.com/0xysh/claude-usage-tracker",
            "https://github.com/0xysh/claude-usage-tracker?redirect=elsewhere",
            "https://github.com/0xysh/claude-usage-tracker#fragment",
            "https://github.com/0xysh/claude-usage-tracker/issues",
            "https://github.com/0xysh/..",
            "not a repository URL"
        ]
        for repository in invalidRepositories {
            XCTAssertNil(FeedbackIssueURL.makeURL(
                repositoryURL: repository, role: "Developer", message: "Feedback"
            ), repository)
        }
    }

    func testASCIIMessageFitsExactlyAtEncodedURLByteCap() throws {
        let smallestURL = try XCTUnwrap(FeedbackIssueURL.makeURL(
            repositoryURL: repositoryURL, role: "Developer", message: "a"
        ))
        let overhead = smallestURL.absoluteString.utf8.count - 1
        let message = String(repeating: "a", count: FeedbackIssueURL.maximumURLBytes - overhead)
        let url = try XCTUnwrap(FeedbackIssueURL.makeURL(
            repositoryURL: repositoryURL, role: "Developer", message: message
        ))
        XCTAssertEqual(url.absoluteString.utf8.count, FeedbackIssueURL.maximumURLBytes)

        let overLimit = FeedbackIssueURL.makeDraftURL(
            repositoryURL: repositoryURL, role: "Developer", message: message + "a"
        )
        guard case .failure(.tooLong) = overLimit else {
            return XCTFail("One byte over the app's draft URL cap must report tooLong")
        }
    }

    func testLargeASCIIMessageIsRejectedWithoutSilentTruncation() {
        let message = String(repeating: "a", count: 10_000)
        let result = FeedbackIssueURL.makeDraftURL(
            repositoryURL: repositoryURL, role: "Developer", message: message
        )
        guard case .failure(.tooLong) = result else {
            return XCTFail("An oversized message must report tooLong rather than produce a truncated draft")
        }
        XCTAssertEqual(message.count, 10_000)
    }

    func testUnicodeLimitUsesPercentEncodedURLBytes() {
        let message = String(repeating: "🧭", count: 1_000)
        XCTAssertLessThan(message.utf8.count, FeedbackIssueURL.maximumURLBytes,
                          "The unencoded message fits, but its percent-encoded URL must not")
        let result = FeedbackIssueURL.makeDraftURL(
            repositoryURL: repositoryURL, role: "Developer", message: message
        )
        guard case .failure(.tooLong) = result else {
            return XCTFail("Unicode expansion must count toward the encoded URL byte cap")
        }
    }
}
