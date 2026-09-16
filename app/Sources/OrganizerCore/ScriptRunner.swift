//
// ScriptRunner.swift
//
// Runs one script through /usr/bin/osascript and streams its output as it
// arrives. osascript writes `log` lines to stderr while the script runs and the
// return value to stdout at the end, so both pipes are read, line by line, on
// a background queue and delivered in order through an AsyncStream.
//

import Foundation

public enum OutputChannel: Sendable, Equatable {
    case stdout
    case stderr
}

public struct OutputLine: Sendable, Equatable {
    public let channel: OutputChannel
    public let text: String
    public let timestamp: Date

    public init(channel: OutputChannel, text: String, timestamp: Date = Date()) {
        self.channel = channel
        self.text = text
        self.timestamp = timestamp
    }
}

public enum RunEvent: Sendable, Equatable {
    case started
    case line(OutputLine)
    /// `stopped` is true when the process ended because `stop()` was called.
    case exited(status: Int32, stopped: Bool)
}

public final class ScriptRunner: @unchecked Sendable {
    public static let osascript = URL(fileURLWithPath: "/usr/bin/osascript")

    private let queue = DispatchQueue(label: "organizer.script-runner")
    private var process: Process?
    private var stopRequested = false

    public init() {}

    /// Launches `osascript <script> <arguments>` and yields its output. The
    /// stream finishes after `.exited`, once both pipes have drained.
    public func run(script: URL, arguments: [String], currentDirectory: URL? = nil) -> AsyncStream<RunEvent> {
        AsyncStream { continuation in
            let process = Process()
            process.executableURL = Self.osascript
            process.arguments = [script.path] + arguments
            process.currentDirectoryURL = currentDirectory ?? script.deletingLastPathComponent()

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = FileHandle.nullDevice

            // All of this state is touched only on `queue`.
            var buffers: [OutputChannel: LineBuffer] = [.stdout: LineBuffer(), .stderr: LineBuffer()]
            var closed: Set<OutputChannel> = []
            var exitStatus: Int32?

            let finishIfDone = { [weak self] in
                guard closed.count == 2, let status = exitStatus else { return }
                let stopped = self?.stopRequested ?? false
                self?.process = nil
                continuation.yield(.exited(status: status, stopped: stopped))
                continuation.finish()
            }

            let attach = { (handle: FileHandle, channel: OutputChannel) in
                handle.readabilityHandler = { [queue = self.queue] h in
                    let data = h.availableData
                    // EOF. Drop the handler here, on its own thread: it can fire
                    // again before the queue gets to it, and the pipe must be
                    // counted closed exactly once.
                    if data.isEmpty { h.readabilityHandler = nil }
                    queue.async {
                        if data.isEmpty {
                            guard !closed.contains(channel) else { return }
                            closed.insert(channel)
                            if let rest = buffers[channel]!.flush() {
                                continuation.yield(.line(OutputLine(channel: channel, text: rest)))
                            }
                            finishIfDone()
                        } else {
                            for text in buffers[channel]!.append(data) {
                                continuation.yield(.line(OutputLine(channel: channel, text: text)))
                            }
                        }
                    }
                }
            }
            attach(stdout.fileHandleForReading, .stdout)
            attach(stderr.fileHandleForReading, .stderr)

            process.terminationHandler = { [queue = self.queue] p in
                queue.async {
                    exitStatus = p.terminationStatus
                    finishIfDone()
                }
            }

            queue.sync {
                self.stopRequested = false
                self.process = process
            }
            do {
                try process.run()
                continuation.yield(.started)
            } catch {
                queue.async {
                    continuation.yield(.line(OutputLine(channel: .stderr, text: "could not launch osascript: \(error.localizedDescription)")))
                    continuation.yield(.exited(status: 127, stopped: false))
                    continuation.finish()
                }
            }

            continuation.onTermination = { [weak self] _ in self?.stop() }
        }
    }

    /// Terminates the running script, if any. A download the script already
    /// queued in Music keeps going; only the script stops.
    public func stop() {
        queue.async { self.terminateLocked() }
    }

    /// The same, but does not return until the signal has been sent: for the
    /// app's own termination, when there is no later turn of the queue.
    public func stopAndWait() {
        queue.sync { self.terminateLocked() }
    }

    private func terminateLocked() {
        guard let p = process, p.isRunning else { return }
        stopRequested = true
        p.terminate()
    }
}
