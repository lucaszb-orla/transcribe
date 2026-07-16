import Foundation
import os

/// Runs the Claude Code CLI headless inside a chosen git repo to implement a `DevSpec` end to end:
/// branch, implement, commit, push, open a PR. On-device orchestration only — the actual coding
/// agent (`claude`) and `git`/`gh` do the real work; this just wires the subprocess together and
/// streams its progress back to the UI.
enum ClaudeCodeRunner {
    private static let log = Logger(subsystem: "com.lucasbaggiotto.Transcribe", category: "ClaudeCodeRunner")

    enum RunnerError: LocalizedError {
        case toolNotFound(String)
        case repoNotFound
        case repoDirty
        case runFailed(String)
        case prNotFound(finalText: String)

        var errorDescription: String? {
            switch self {
            case .toolNotFound(let tool):
                return "Não encontrei o `\(tool)` no PATH deste Mac. Confirme que está instalado e autenticado, e tente de novo."
            case .repoNotFound:
                return "A pasta escolhida não existe mais ou não é um repositório git válido."
            case .repoDirty:
                return "O repositório tem alterações não commitadas. Faça commit ou stash antes de rodar a automação."
            case .runFailed(let message):
                return "A automação falhou: \(message)"
            case .prNotFound(let finalText):
                return "O Claude Code terminou, mas não encontrei uma Pull Request aberta para essa branch. Confira o repositório manualmente. Última mensagem: \(finalText)"
            }
        }
    }

    static func run(
        spec: DevSpec,
        meetingMarkdown: String,
        repoPath: String,
        onLog: @escaping @MainActor (String) -> Void
    ) async throws -> DevSpecResult {
        let tools = try await resolveTools()
        try await checkRepo(at: repoPath, git: tools.git)

        let branch = branchName(for: spec)
        await onLog("Iniciando automação na branch \(branch)…")

        let finalText = try await runClaude(
            spec: spec,
            branch: branch,
            meetingMarkdown: meetingMarkdown,
            repoPath: repoPath,
            claudePath: tools.claude,
            pathEnv: tools.pathEnv,
            onLog: onLog
        )

        await onLog("Confirmando se a PR foi aberta…")
        if let url = try? await prURL(repoPath: repoPath, branch: branch, gh: tools.gh) {
            return DevSpecResult(status: .success, prURL: url, message: "PR aberta com sucesso.", finishedAt: Date())
        }
        // Claude may have picked a slightly different branch name despite the instruction; check HEAD.
        if let head = try? await currentBranch(repoPath: repoPath, git: tools.git), head != branch,
           let url = try? await prURL(repoPath: repoPath, branch: head, gh: tools.gh) {
            return DevSpecResult(status: .success, prURL: url, message: "PR aberta com sucesso.", finishedAt: Date())
        }
        throw RunnerError.prNotFound(finalText: finalText)
    }

    // MARK: - Preflight

    private struct Tools {
        var claude: String
        var git: String
        var gh: String
        var pathEnv: String
    }

    /// GUI apps don't inherit the user's shell PATH (no `.zshrc`/homebrew/nvm sourcing), so resolve
    /// everything through one login-shell call: the tool paths, and the PATH itself (needed so the
    /// `claude` subprocess can find `git`/`gh` when it shells out on its own).
    private static func resolveTools() async throws -> Tools {
        let script = "echo \"$PATH\"; command -v claude; command -v git; command -v gh"
        let (output, _) = try await runProcess("/bin/zsh", ["-l", "-c", script])
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let pathEnv = lines.first ?? ""
        let claude = lines.count > 1 ? lines[1].trimmingCharacters(in: .whitespaces) : ""
        let git = lines.count > 2 ? lines[2].trimmingCharacters(in: .whitespaces) : ""
        let gh = lines.count > 3 ? lines[3].trimmingCharacters(in: .whitespaces) : ""
        guard !claude.isEmpty else { throw RunnerError.toolNotFound("claude") }
        guard !git.isEmpty else { throw RunnerError.toolNotFound("git") }
        guard !gh.isEmpty else { throw RunnerError.toolNotFound("gh") }
        return Tools(claude: claude, git: git, gh: gh, pathEnv: pathEnv)
    }

    private static func checkRepo(at repoPath: String, git: String) async throws {
        guard FileManager.default.fileExists(atPath: repoPath) else { throw RunnerError.repoNotFound }
        let (isRepo, rc) = try await runProcess(git, ["-C", repoPath, "rev-parse", "--is-inside-work-tree"])
        guard rc == 0, isRepo.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            throw RunnerError.repoNotFound
        }
        let (status, _) = try await runProcess(git, ["-C", repoPath, "status", "--porcelain"])
        guard status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RunnerError.repoDirty
        }
    }

    private static func currentBranch(repoPath: String, git: String) async throws -> String {
        let (out, _) = try await runProcess(git, ["-C", repoPath, "rev-parse", "--abbrev-ref", "HEAD"])
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func prURL(repoPath: String, branch: String, gh: String) async throws -> String {
        let (out, rc) = try await runProcess(gh, ["-C", repoPath, "pr", "view", branch, "--json", "url", "-q", ".url"])
        let url = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rc == 0, !url.isEmpty else { throw RunnerError.prNotFound(finalText: "") }
        return url
    }

    static func branchName(for spec: DevSpec) -> String {
        let slug = spec.title
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .init(identifier: "pt_BR"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let shortID = spec.id.uuidString.prefix(6).lowercased()
        let base = slug.isEmpty ? "tarefa" : String(slug.prefix(40))
        return "transcribe/\(base)-\(shortID)"
    }

    // MARK: - Claude Code invocation

    private static func runClaude(
        spec: DevSpec,
        branch: String,
        meetingMarkdown: String,
        repoPath: String,
        claudePath: String,
        pathEnv: String,
        onLog: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        let prompt = """
        Você é um agente de desenvolvimento autônomo rodando dentro de um repositório git local. \
        Implemente a tarefa a seguir, cuide de build/testes se o projeto tiver, e então: \
        crie a branch "\(branch)" a partir do HEAD atual, faça commit das mudanças com uma mensagem \
        descritiva, dê push da branch (`git push -u origin \(branch)`), e abra uma Pull Request contra \
        a branch padrão do repositório com `gh pr create` (título e descrição condizentes com a mudança). \
        Ao final, imprima a URL da PR criada.

        Contexto completo da reunião que originou esta tarefa foi enviado via stdin (formato Markdown).

        Título da tarefa: \(spec.title)
        Descrição: \(spec.description)
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        process.arguments = [
            "-p", prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--permission-mode", "acceptEdits",
            "--allowedTools", "Bash",
        ]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = pathEnv
        process.environment = env

        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = Pipe() // drained but not surfaced; claude's own stdout carries the log

        // ponytail: readabilityHandler runs on its own queue and mutates these without a lock; the
        // only read of `finalText` happens after termination, which in practice always lands after
        // the last chunk is delivered. Upgrade to a proper actor/lock if this ever proves flaky.
        var finalText = ""
        var buffer = Data()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            buffer.append(chunk)
            while let range = buffer.firstRange(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                    if let text = describeEvent(line) {
                        Task { @MainActor in onLog(text) }
                    }
                    if let result = finalResultText(line) {
                        finalText = result
                    }
                }
            }
        }

        try process.run()
        if let data = meetingMarkdown.data(using: .utf8) {
            stdin.fileHandleForWriting.write(data)
        }
        try stdin.fileHandleForWriting.close()

        // If the enclosing Task is cancelled (view torn down, app quitting), kill the child process
        // instead of leaving it orphaned in the background.
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                process.terminationHandler = { _ in continuation.resume() }
            }
        } onCancel: {
            process.terminate()
        }
        stdout.fileHandleForReading.readabilityHandler = nil

        guard process.terminationStatus == 0 else {
            throw RunnerError.runFailed(finalText.isEmpty ? "processo saiu com código \(process.terminationStatus)." : finalText)
        }
        return finalText
    }

    /// Best-effort NDJSON → human log line. Unknown/uninteresting event shapes are silently skipped;
    /// ceiling: this doesn't attempt to fully model every Claude Code stream-json event type.
    static func describeEvent(_ line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return nil }

        switch type {
        case "assistant":
            guard let message = obj["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return nil }
            var lines: [String] = []
            for block in content {
                switch block["type"] as? String {
                case "text":
                    if let text = block["text"] as? String, !text.isEmpty { lines.append(text) }
                case "tool_use":
                    let name = block["name"] as? String ?? "ferramenta"
                    if let input = block["input"] as? [String: Any], let command = input["command"] as? String {
                        lines.append("→ \(command)")
                    } else {
                        lines.append("→ \(name)")
                    }
                default:
                    break
                }
            }
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        case "result":
            let text = obj["result"] as? String ?? ""
            return text.isEmpty ? nil : text
        default:
            return nil
        }
    }

    static func finalResultText(_ line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["type"] as? String == "result" else { return nil }
        return obj["result"] as? String ?? ""
    }

    // MARK: - Generic process helper

    @discardableResult
    private static func runProcess(_ executable: String, _ args: [String]) async throws -> (output: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
        }
        return (String(data: data, encoding: .utf8) ?? "", process.terminationStatus)
    }
}
