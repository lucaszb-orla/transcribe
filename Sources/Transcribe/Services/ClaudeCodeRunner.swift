import AppKit
import Foundation
import os

/// Prepares a `DevSpec` for the Claude Code CLI and hands it off to a visible Terminal window —
/// deliberately not a hidden background automation: the user watches (and can take over) a real
/// `claude -p` run instead of the app trying to babysit/parse a subprocess itself.
enum ClaudeCodeRunner {
    private static let log = Logger(subsystem: "com.lucasbaggiotto.Transcribe", category: "ClaudeCodeRunner")

    enum DevSpecStatus: Equatable {
        case notStarted
        case dispatched
        case prOpen(url: String)
        case prMerged(url: String)
        case prClosed(url: String)
    }

    enum RunnerError: LocalizedError {
        case repoNotFound
        case repoDirty
        case toolNotFound(String)
        case invalidGeneration(String)

        var errorDescription: String? {
            switch self {
            case .repoNotFound:
                return String(localized: "A pasta escolhida não existe mais ou não é um repositório git válido.")
            case .repoDirty:
                return String(localized: "O repositório tem alterações não commitadas. Faça commit ou stash antes de rodar a automação.")
            case .toolNotFound(let tool):
                return String(localized: "Não encontrei o `\(tool)` no PATH deste Mac. Confirme que está instalado e autenticado, e tente de novo.")
            case .invalidGeneration(let text):
                return String(localized: "O Claude não devolveu uma lista de specs válida. Resposta recebida: \(text.prefix(200))")
            }
        }
    }

    /// Generates the spec list by having the real `claude` CLI read the transcript directly —
    /// no context-window juggling needed, and much more accurate than the on-device model. Runs
    /// headless with no tool access at all (pure text-in/JSON-out), so nothing pops up on screen.
    static func generateDevSpecs(transcript: String, calendarContext: String?, customInstructions: String, options: DevSpecOptions) async throws -> [DevSpec] {
        guard let claude = await resolveTool("claude") else { throw RunnerError.toolNotFound("claude") }

        var lines = [
            "Leia a transcrição de reunião de trabalho em português do Brasil enviada via stdin e identifique",
            "tarefas de implementação de software distintas mencionadas nela, sem inventar informação que não",
            "está no texto. Devolva SOMENTE um JSON no formato [{\"title\": \"...\", \"description\": \"...\"}] —",
            "nenhum texto antes ou depois, nenhum bloco de código markdown. Se nada for acionável, devolva [].",
        ]
        let custom = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { lines.append("Instruções adicionais do usuário: \(custom)") }
        if let calendarContext, !calendarContext.isEmpty { lines.append("Contexto do evento de calendário: \(calendarContext)") }
        let prompt = lines.joined(separator: " ")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claude)
        process.arguments = ["-p", prompt, "--model", options.model.rawValue, "--effort", options.effort.rawValue]

        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        try process.run()
        if let data = transcript.data(using: .utf8) { stdin.fileHandleForWriting.write(data) }
        try stdin.fileHandleForWriting.close()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
        }

        return try parseDevSpecs(from: String(data: data, encoding: .utf8) ?? "")
    }

    static func parseDevSpecs(from text: String) throws -> [DevSpec] {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw RunnerError.invalidGeneration(cleaned)
        }
        return raw.compactMap { obj in
            guard let title = obj["title"] as? String, let description = obj["description"] as? String else { return nil }
            return DevSpec(title: title, description: description)
        }
    }

    /// Checks the repo is usable, builds the branch name + prompt, writes a `.command` script and
    /// opens it in Terminal. `git` is looked up at its fixed system path — no PATH resolution needed
    /// since Terminal itself (not this process) is what ends up running `claude`/`gh`.
    @MainActor
    static func openInTerminal(spec: DevSpec, meetingMarkdown: String, repoPath: String, options: DevSpecOptions) async throws {
        try await checkRepo(at: repoPath)
        let branch = branchName(for: spec)
        let script = buildScript(spec: spec, branch: branch, meetingMarkdown: meetingMarkdown, repoPath: repoPath, options: options)
        // Named after the branch slug (not a raw UUID) so Terminal's window title identifies which
        // spec is running when several are open at once — a `.command`'s filename is its title.
        let fileName = branch.replacingOccurrences(of: "transcribe/", with: "")
        let url = try writeScript(script, named: fileName)
        NSWorkspace.shared.open(url)
    }

    /// A quick, read-only look at whether a previously-dispatched spec has an open/merged/closed PR
    /// yet. Never throws — worst case it just reports `.dispatched` (sent, nothing found yet).
    static func checkStatus(spec: DevSpec, repoPath: String) async -> DevSpecStatus {
        guard spec.lastDispatchedAt != nil else { return .notStarted }
        guard let gh = await resolveTool("gh") else { return .dispatched }
        let branch = branchName(for: spec)
        guard let (out, rc) = try? await runProcess(gh, ["-C", repoPath, "pr", "view", branch, "--json", "url,state", "-q", ".url + \"|\" + .state"]),
              rc == 0 else { return .dispatched }
        let parts = out.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", maxSplits: 1)
        guard parts.count == 2 else { return .dispatched }
        let url = String(parts[0])
        switch String(parts[1]) {
        case "MERGED": return .prMerged(url: url)
        case "CLOSED": return .prClosed(url: url)
        default: return .prOpen(url: url)
        }
    }

    /// `gh`/`claude` (unlike `git`) aren't at a fixed system path — resolve via a login shell: this
    /// app process doesn't inherit the user's shell PATH the way Terminal-launched scripts do.
    private static func resolveTool(_ name: String) async -> String? {
        guard let (out, rc) = try? await runProcess("/bin/zsh", ["-l", "-c", "command -v \(name)"]), rc == 0 else { return nil }
        let path = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    // MARK: - Preflight

    private static func checkRepo(at repoPath: String) async throws {
        guard FileManager.default.fileExists(atPath: repoPath) else { throw RunnerError.repoNotFound }
        let (isRepo, rc) = try await runProcess("/usr/bin/git", ["-C", repoPath, "rev-parse", "--is-inside-work-tree"])
        guard rc == 0, isRepo.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            throw RunnerError.repoNotFound
        }
        let (status, _) = try await runProcess("/usr/bin/git", ["-C", repoPath, "status", "--porcelain"])
        guard status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RunnerError.repoDirty
        }
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

    // MARK: - Script

    static func buildScript(spec: DevSpec, branch: String, meetingMarkdown: String, repoPath: String, options: DevSpecOptions) -> String {
        let promptDelimiter = "TRANSCRIBE_PROMPT_\(spec.id.uuidString.prefix(8))"
        let contextDelimiter = "TRANSCRIBE_CONTEXT_\(spec.id.uuidString.prefix(8))"
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
        return """
        #!/bin/zsh
        cd \(shellQuote(repoPath)) || { echo "Não consegui entrar em \(repoPath)"; exec zsh -l }
        PROMPT=$(cat <<'\(promptDelimiter)'
        \(prompt)
        \(promptDelimiter)
        )
        cat <<'\(contextDelimiter)' | claude -p "$PROMPT" --model \(options.model.rawValue) --effort \(options.effort.rawValue) --permission-mode acceptEdits --allowedTools Bash
        \(meetingMarkdown)
        \(contextDelimiter)
        exec zsh -l
        """
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func writeScript(_ content: String, named fileName: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Transcribe", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeName = fileName.isEmpty ? "claude-run-\(UUID().uuidString)" : fileName
        let url = dir.appendingPathComponent("\(safeName).command")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        } catch {
            log.error("failed to write launch script: \(String(describing: error), privacy: .public)")
            throw error
        }
        return url
    }

    // MARK: - Generic process helper

    @discardableResult
    private static func runProcess(_ executable: String, _ args: [String]) async throws -> (output: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let stdout = Pipe()
        process.standardOutput = stdout
        // Not a Pipe(): an unread pipe fills its buffer and deadlocks the child the moment it writes
        // enough to stderr — this made an earlier version of this code hang forever.
        process.standardError = FileHandle.nullDevice

        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
        }
        return (String(data: data, encoding: .utf8) ?? "", process.terminationStatus)
    }
}
