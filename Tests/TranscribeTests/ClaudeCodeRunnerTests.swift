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

    func testBuildScriptContainsRepoAndBranchAndCommand() {
        let spec = DevSpec(title: "Adicionar endpoint /health", description: "Retorna OK")
        let branch = ClaudeCodeRunner.branchName(for: spec)
        let script = ClaudeCodeRunner.buildScript(
            spec: spec,
            branch: branch,
            meetingMarkdown: "# Reunião\n\nConteúdo de teste",
            repoPath: "/tmp/some repo"
        )
        XCTAssertTrue(script.hasPrefix("#!/bin/zsh"))
        XCTAssertTrue(script.contains("cd '/tmp/some repo'"))
        XCTAssertTrue(script.contains(branch))
        XCTAssertTrue(script.contains("claude -p \"$PROMPT\""))
        XCTAssertTrue(script.contains("Conteúdo de teste"))
    }

    func testBuildScriptUsesDistinctDelimitersPerSpec() {
        let specA = DevSpec(title: "A", description: "")
        let specB = DevSpec(title: "B", description: "")
        let scriptA = ClaudeCodeRunner.buildScript(spec: specA, branch: "x", meetingMarkdown: "", repoPath: "/tmp/r")
        let scriptB = ClaudeCodeRunner.buildScript(spec: specB, branch: "x", meetingMarkdown: "", repoPath: "/tmp/r")
        XCTAssertNotEqual(scriptA, scriptB)
    }
}
