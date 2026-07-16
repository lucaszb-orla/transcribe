import XCTest
@testable import Transcribe

final class ClaudeCodeRunnerTests: XCTestCase {
    func testBranchNameSlugifiesAccentedTitle() {
        let spec = DevSpec(title: "Adicionar endpoint de saúde!", description: "")
        let branch = ClaudeCodeRunner.branchName(for: spec)
        XCTAssertTrue(branch.hasPrefix("transcribe/adicionar-endpoint-de-saude-"))
        XCTAssertFalse(branch.contains(" "))
    }

    func testBranchNameFallsBackWhenTitleHasNoAlphanumerics() {
        let spec = DevSpec(title: "!!!", description: "")
        let branch = ClaudeCodeRunner.branchName(for: spec)
        XCTAssertTrue(branch.hasPrefix("transcribe/tarefa-"))
    }

    func testDescribeEventExtractsAssistantText() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Implementando o endpoint"}]}}"#
        XCTAssertEqual(ClaudeCodeRunner.describeEvent(line), "Implementando o endpoint")
    }

    func testDescribeEventExtractsToolUseCommand() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"git commit -m x"}}]}}"#
        XCTAssertEqual(ClaudeCodeRunner.describeEvent(line), "→ git commit -m x")
    }

    func testDescribeEventIgnoresUnknownEventTypes() {
        let line = #"{"type":"system","subtype":"init"}"#
        XCTAssertNil(ClaudeCodeRunner.describeEvent(line))
    }

    func testFinalResultTextExtractsResultLine() {
        let line = #"{"type":"result","subtype":"success","is_error":false,"result":"PR aberta: https://github.com/x/y/pull/1"}"#
        XCTAssertEqual(ClaudeCodeRunner.finalResultText(line), "PR aberta: https://github.com/x/y/pull/1")
    }

    func testFinalResultTextNilForNonResultLine() {
        let line = #"{"type":"assistant","message":{"content":[]}}"#
        XCTAssertNil(ClaudeCodeRunner.finalResultText(line))
    }
}
