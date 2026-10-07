import XCTest
@testable import Claude_Usage

@MainActor
final class UsagePollingRequestTests: XCTestCase {
    func testClaudeOAuthPollingReadsUsageWithoutGeneratingAMessage() async {
        let request = UsagePollingRequest.claudeOAuth(accessToken: "synthetic-token")
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/api/oauth/usage")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
    }

    func testCodexOfficialHostsUseUsageEndpointAndAccountHeader() async throws {
        for base in ["https://chatgpt.com/", "https://chatgpt.com/backend-api", "https://chat.openai.com"] {
            let request = try UsagePollingRequest.codex(baseURL: base, accessToken: "synthetic-token", accountID: "synthetic-account")
            XCTAssertEqual(request.url?.path, "/backend-api/wham/usage")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.httpBody)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "synthetic-account")
        }
    }

    func testCodexRejectsUntrustedAndAmbiguousDestinationsBeforeBuildingBearerRequest() async {
        let invalid = [
            "http://chatgpt.com/backend-api", "https://chatgpt.com.attacker.example",
            "https://chatgpt.com@attacker.example", "https://user:password@chatgpt.com",
            "https://chatgpt.com:444", "https://chatgpt.com/backend-api?token=secret",
            "https://chatgpt.com/backend-api#fragment", "https://chatgpt.com/unrelated",
            "https://proxy.corp.com", "file:///tmp/auth", "not a URL"
        ]
        for base in invalid {
            XCTAssertThrowsError(try UsagePollingRequest.codex(baseURL: base, accessToken: "synthetic-token", accountID: nil), base)
        }
    }
}
