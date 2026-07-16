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
            repoPath: "/tmp/some repo",
            options: DevSpecOptions(model: .opus, effort: .high)
        )
        XCTAssertTrue(script.hasPrefix("#!/bin/zsh"))
        XCTAssertTrue(script.contains("cd '/tmp/some repo'"))
        XCTAssertTrue(script.contains(branch))
        XCTAssertTrue(script.contains("claude -p \"$PROMPT\" --model opus --effort high"))
        XCTAssertTrue(script.contains("Conteúdo de teste"))
    }

    func testBuildScriptUsesDistinctDelimitersPerSpec() {
        let specA = DevSpec(title: "A", description: "")
        let specB = DevSpec(title: "B", description: "")
        let options = DevSpecOptions()
        let scriptA = ClaudeCodeRunner.buildScript(spec: specA, branch: "x", meetingMarkdown: "", repoPath: "/tmp/r", options: options)
        let scriptB = ClaudeCodeRunner.buildScript(spec: specB, branch: "x", meetingMarkdown: "", repoPath: "/tmp/r", options: options)
        XCTAssertNotEqual(scriptA, scriptB)
    }

    func testParseDevSpecsDecodesPlainJSON() throws {
        let specs = try ClaudeCodeRunner.parseDevSpecs(from: #"[{"title":"A","description":"B"}]"#)
        XCTAssertEqual(specs.map(\.title), ["A"])
        XCTAssertEqual(specs.map(\.description), ["B"])
    }

    func testParseDevSpecsStripsMarkdownCodeFence() throws {
        let text = "```json\n[{\"title\":\"A\",\"description\":\"B\"}]\n```"
        let specs = try ClaudeCodeRunner.parseDevSpecs(from: text)
        XCTAssertEqual(specs.map(\.title), ["A"])
    }

    func testParseDevSpecsReturnsEmptyForEmptyArray() throws {
        XCTAssertEqual(try ClaudeCodeRunner.parseDevSpecs(from: "[]"), [])
    }

    func testParseDevSpecsThrowsOnGarbage() {
        XCTAssertThrowsError(try ClaudeCodeRunner.parseDevSpecs(from: "desculpe, não consigo ajudar com isso"))
    }
}
