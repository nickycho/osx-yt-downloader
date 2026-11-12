import Foundation

struct ProcessResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

struct ProcessRunner {
    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String] = [:],
        onStdout: (@Sendable (String) -> Void)? = nil,
        onStderr: (@Sendable (String) -> Void)? = nil
    ) async throws -> ProcessResult {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            if !environment.isEmpty {
                process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
            }

            do {
                try process.run()
            } catch {
                throw ProcessRunnerError.launchFailed(executable: executable, underlying: error)
            }

            let stdoutTask = Task.detached(priority: .utility) {
                Self.readOutput(from: stdoutPipe.fileHandleForReading, onChunk: onStdout)
            }
            let stderrTask = Task.detached(priority: .utility) {
                Self.readOutput(from: stderrPipe.fileHandleForReading, onChunk: onStderr)
            }

            process.waitUntilExit()

            let stdout = await stdoutTask.value
            let stderr = await stderrTask.value
            let result = ProcessResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)

            guard result.exitCode == 0 else {
                throw ProcessRunnerError.nonZeroExit(result)
            }

            return result
        }.value
    }

    private static func readOutput(
        from handle: FileHandle,
        onChunk: (@Sendable (String) -> Void)?
    ) -> String {
        var collected = Data()

        while true {
            let chunk = handle.readData(ofLength: 4096)
            guard !chunk.isEmpty else { break }
            collected.append(chunk)
            if let onChunk {
                onChunk(String(decoding: chunk, as: UTF8.self))
            }
        }

        return String(decoding: collected, as: UTF8.self)
    }
}

enum ProcessRunnerError: LocalizedError {
    case launchFailed(executable: URL, underlying: Error)
    case nonZeroExit(ProcessResult)

    var errorDescription: String? {
        switch self {
        case let .launchFailed(executable, underlying):
            return "無法啟動工具 \(executable.lastPathComponent)：\(underlying.localizedDescription)"
        case let .nonZeroExit(result):
            let details = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return details.isEmpty ? "工具執行失敗（代碼 \(result.exitCode)）。" : details
        }
    }

    var processResult: ProcessResult? {
        guard case let .nonZeroExit(result) = self else { return nil }
        return result
    }
}
