import CoreFoundation
import Darwin
import Foundation

/// Invoked before App startup. No store, window, quota RPC, or credential API is involved.
enum ClaudeStatuslineBridge {
    static let argument = "--claude-statusline-bridge"

    static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Int32? {
        guard arguments.dropFirst().first == argument else { return nil }
        guard arguments.count == 3 else { return 2 }
        let cancellation = CancellationState()
        do {
            let url = URL(fileURLWithPath: arguments[2])
            let manifest = try manifest(at: url)
            let value = UserDefaults.standard.object(forKey: "claudeMonitoringEnabled.v1") as? NSNumber
            let enabled = value.map { CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue } ?? false
            let status = try forward(manifest: manifest, captureEnabled: enabled, cancellation: cancellation)
            return cancellation.exitStatus ?? status
        } catch { return cancellation.exitStatus ?? 2 }
    }

    static func capture(_ data: Data, manifestURL: URL, enabled: Bool, now: Date = Date()) throws {
        guard enabled else { return }
        let value = try manifest(at: manifestURL)
        try ClaudeStatuslineCache(fileURL: URL(fileURLWithPath: value.cachePath)).capture(data, at: now)
    }

    private static func manifest(at url: URL) throws -> ClaudeStatuslineInstaller.Manifest {
        let data = try ClaudeLocalFile.read(url, maximumBytes: 1_048_576)
        guard let value = try? JSONDecoder().decode(ClaudeStatuslineInstaller.Manifest.self, from: data),
              value.version == 1, URL(fileURLWithPath: value.cachePath).isFileURL,
              value.cachePath.hasPrefix("/"), value.settingsPath.hasPrefix("/") else {
            throw ClaudeQuotaIssue.configurationConflict
        }
        return value
    }

    private final class CancellationState: @unchecked Sendable {
        private let lock = NSLock()
        private var firstSignal: Int32?

        func record(_ number: Int32) -> Int32 {
            lock.withLock {
                if firstSignal == nil { firstSignal = number }
                return 128 + (firstSignal ?? number)
            }
        }

        var exitStatus: Int32? { lock.withLock { firstSignal.map { 128 + $0 } } }
    }

    private static func forward(
        manifest: ClaudeStatuslineInstaller.Manifest,
        captureEnabled: Bool,
        cancellation: CancellationState
    ) throws -> Int32 {
        let lifecycle = ManagedSubprocessLifecycle()
        // Claude cancels statusline commands on updates. Forward cancellation to
        // the separately owned process group, including descendants, before exit.
        let cancellations = [SIGTERM, SIGINT, SIGHUP].map { number -> DispatchSourceSignal in
            // A caught handler is reset to SIG_DFL across exec; SIG_IGN would
            // instead leak into the original command and suppress its TERM trap.
            // The signal handler itself does no work; cleanup runs on the queue.
            signal(number) { _ in }
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global(qos: .utility))
            source.setEventHandler {
                // Publish cancellation before shutdown can make the child exit.
                // The main forwarding path may observe that exit before this
                // handler finishes; both paths must return the same signal code.
                let status = cancellation.record(number)
                lifecycle.shutdown(gracePeriod: 0.2)
                Darwin.exit(status)
            }
            source.resume()
            return source
        }
        defer { cancellations.forEach { $0.cancel() } }
        let input = Pipe()
        let child: ManagedSubprocess?
        if let command = manifest.originalCommand {
            child = try lifecycle.launch {
                try ManagedSubprocess.launch(
                    executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", command],
                    environment: ProcessInfo.processInfo.environment, standardInput: input,
                    standardOutputHandle: FileHandle.standardOutput,
                    standardErrorHandle: FileHandle.standardError
                )
            }
            _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETFL, O_NONBLOCK)
            signal(SIGPIPE, SIG_IGN)
        } else { child = nil }
        defer { lifecycle.shutdown(gracePeriod: 0.2) }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(30))
        var captured = Data()
        var inputFits = true
        var forwardsInput = child != nil
        var bytes = [UInt8](repeating: 0, count: 8_192)
        while true {
            try waitFor(STDIN_FILENO, events: Int16(POLLIN | POLLHUP), until: deadline)
            let count = Darwin.read(STDIN_FILENO, &bytes, bytes.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw ClaudeQuotaIssue.unavailable
            }
            if captureEnabled, inputFits {
                if captured.count + count <= ClaudeStatuslineParser.maximumInputBytes {
                    captured.append(contentsOf: bytes.prefix(count))
                } else { captured.removeAll(); inputFits = false }
            }
            if forwardsInput {
                let descriptor = input.fileHandleForWriting.fileDescriptor
                try bytes.withUnsafeBytes { buffer in
                    var sent = 0
                    while sent < count {
                        try waitFor(descriptor, events: Int16(POLLOUT), until: deadline)
                        let written = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: sent), count - sent)
                        if written > 0 { sent += written }
                        else if written < 0, errno == EPIPE {
                            forwardsInput = false
                            try? input.fileHandleForWriting.close()
                            break
                        } else if written < 0, errno == EINTR || errno == EAGAIN { continue }
                        else { throw ClaudeQuotaIssue.unavailable }
                    }
                }
            }
        }
        try? input.fileHandleForWriting.close()
        if captureEnabled, inputFits, cancellation.exitStatus == nil {
            // A malformed quota payload never changes the pre-existing statusline's output.
            try? ClaudeStatuslineCache(fileURL: URL(fileURLWithPath: manifest.cachePath)).capture(captured)
        }
        guard let child else { return cancellation.exitStatus ?? 0 }
        while !child.pollForExit(), clock.now < deadline { usleep(10_000) }
        guard child.pollForExit() else { throw ClaudeQuotaIssue.timedOut }
        return cancellation.exitStatus ?? child.terminationStatus ?? 2
    }

    private static func waitFor(_ descriptor: Int32, events: Int16, until deadline: ContinuousClock.Instant) throws {
        let clock = ContinuousClock()
        while true {
            let now = clock.now
            guard now < deadline else { throw ClaudeQuotaIssue.timedOut }
            let remaining = now.duration(to: deadline).components
            let milliseconds = Double(remaining.seconds) * 1_000 + Double(remaining.attoseconds) / 1e15
            var value = pollfd(fd: descriptor, events: events, revents: 0)
            let status = poll(&value, 1, Int32(max(1, min(ceil(milliseconds), Double(Int32.max)))))
            if status > 0 { return }
            if status < 0, errno == EINTR { continue }
            throw ClaudeQuotaIssue.timedOut
        }
    }
}
