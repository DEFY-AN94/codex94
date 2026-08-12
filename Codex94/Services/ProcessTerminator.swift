import Darwin
import Foundation

private enum ManagedSubprocessError: Error {
    case invalidInput
    case systemCallFailed(Int32)
}

final class ManagedSubprocess {
    let processIdentifier: pid_t
    let processGroupIdentifier: pid_t

    private let stateLock = NSLock()
    private var waitStatus: Int32?

    private init(processIdentifier: pid_t) {
        self.processIdentifier = processIdentifier
        self.processGroupIdentifier = processIdentifier
    }

    static func launch(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        environment: [String: String],
        standardInput: Pipe? = nil,
        standardOutput: Pipe? = nil
    ) throws -> ManagedSubprocess {
        let executablePath = executableURL.path
        let environmentValues = environment
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
        let stringValues = [executablePath] + arguments + environmentValues
        guard stringValues.allSatisfy({ !$0.utf8.contains(0) }),
              currentDirectoryURL.map({ !$0.path.utf8.contains(0) }) ?? true else {
            throw ManagedSubprocessError.invalidInput
        }

        let nullDescriptor = Darwin.open("/dev/null", O_RDWR | O_CLOEXEC)
        guard nullDescriptor >= 0 else {
            throw ManagedSubprocessError.systemCallFailed(errno)
        }
        defer { Darwin.close(nullDescriptor) }

        var fileActions: posix_spawn_file_actions_t?
        try requireSuccess(posix_spawn_file_actions_init(&fileActions))
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        let inputDescriptor = standardInput?.fileHandleForReading.fileDescriptor ?? nullDescriptor
        let outputDescriptor = standardOutput?.fileHandleForWriting.fileDescriptor ?? nullDescriptor
        try requireSuccess(posix_spawn_file_actions_adddup2(
            &fileActions,
            inputDescriptor,
            STDIN_FILENO
        ))
        try requireSuccess(posix_spawn_file_actions_adddup2(
            &fileActions,
            outputDescriptor,
            STDOUT_FILENO
        ))
        try requireSuccess(posix_spawn_file_actions_adddup2(
            &fileActions,
            nullDescriptor,
            STDERR_FILENO
        ))

        var descriptorsToClose = Set([inputDescriptor, outputDescriptor, nullDescriptor])
        if let standardInput {
            descriptorsToClose.insert(standardInput.fileHandleForWriting.fileDescriptor)
        }
        if let standardOutput {
            descriptorsToClose.insert(standardOutput.fileHandleForReading.fileDescriptor)
        }
        for descriptor in descriptorsToClose.sorted() where descriptor > STDERR_FILENO {
            try requireSuccess(posix_spawn_file_actions_addclose(&fileActions, descriptor))
        }

        if let currentDirectoryURL {
            let changeDirectoryStatus = currentDirectoryURL.path.withCString { path in
                // Xcode 16's SDK exposes only this macOS 10.15-compatible entry point.
                posix_spawn_file_actions_addchdir_np(&fileActions, path)
            }
            try requireSuccess(changeDirectoryStatus)
        }

        var attributes: posix_spawnattr_t?
        try requireSuccess(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }

        // A dedicated group lets cleanup include helpers spawned by Codex.
        let flags = Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)
        try requireSuccess(posix_spawnattr_setflags(&attributes, flags))
        try requireSuccess(posix_spawnattr_setpgroup(&attributes, 0))

        var argumentPointers = try duplicateCStringArray([executablePath] + arguments)
        defer { freeCStringArray(argumentPointers) }
        var environmentPointers = try duplicateCStringArray(environmentValues)
        defer { freeCStringArray(environmentPointers) }

        var processIdentifier: pid_t = 0
        let launchStatus = executablePath.withCString { executablePointer in
            argumentPointers.withUnsafeMutableBufferPointer { argumentsBuffer in
                environmentPointers.withUnsafeMutableBufferPointer { environmentBuffer in
                    posix_spawn(
                        &processIdentifier,
                        executablePointer,
                        &fileActions,
                        &attributes,
                        argumentsBuffer.baseAddress,
                        environmentBuffer.baseAddress
                    )
                }
            }
        }
        try requireSuccess(launchStatus)

        try? standardInput?.fileHandleForReading.close()
        try? standardOutput?.fileHandleForWriting.close()
        return ManagedSubprocess(processIdentifier: processIdentifier)
    }

    var terminationStatus: Int32? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let waitStatus else { return nil }
        if waitStatus & 0x7F == 0 {
            return (waitStatus >> 8) & 0xFF
        }
        return 128 + (waitStatus & 0x7F)
    }

    @discardableResult
    func pollForExit() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard waitStatus == nil else { return true }

        while true {
            var status: Int32 = 0
            let result = waitpid(processIdentifier, &status, WNOHANG)
            if result == processIdentifier {
                waitStatus = status
                return true
            }
            if result == 0 { return false }
            if errno == EINTR { continue }
            return errno == ECHILD
        }
    }

    func waitUntilExit(before deadline: Date) -> Bool {
        while Date() < deadline {
            if pollForExit() { return true }
            usleep(20_000)
        }
        return pollForExit()
    }

    func waitUntilExit() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard waitStatus == nil else { return }

        while true {
            var status: Int32 = 0
            let result = waitpid(processIdentifier, &status, 0)
            if result == processIdentifier {
                waitStatus = status
                return
            }
            if result < 0, errno == EINTR { continue }
            return
        }
    }

    func signalProcessGroup(_ signal: Int32) {
        Darwin.kill(-processGroupIdentifier, signal)
    }

    var isProcessGroupRunning: Bool {
        if Darwin.kill(-processGroupIdentifier, 0) == 0 { return true }
        return errno == EPERM
    }

    private static func requireSuccess(_ status: Int32) throws {
        guard status == 0 else {
            throw ManagedSubprocessError.systemCallFailed(status)
        }
    }

    private static func duplicateCStringArray(
        _ strings: [String]
    ) throws -> [UnsafeMutablePointer<CChar>?] {
        var pointers: [UnsafeMutablePointer<CChar>?] = []
        for string in strings {
            guard let pointer = strdup(string) else {
                freeCStringArray(pointers)
                throw ManagedSubprocessError.systemCallFailed(ENOMEM)
            }
            pointers.append(pointer)
        }
        pointers.append(nil)
        return pointers
    }

    private static func freeCStringArray(_ pointers: [UnsafeMutablePointer<CChar>?]) {
        for pointer in pointers {
            free(pointer)
        }
    }
}

enum ProcessTerminator {
    static func stop(_ process: ManagedSubprocess, gracePeriod: TimeInterval) {
        process.signalProcessGroup(SIGTERM)
        let deadline = Date().addingTimeInterval(gracePeriod)
        while process.isProcessGroupRunning, Date() < deadline {
            process.pollForExit()
            usleep(20_000)
        }

        if process.isProcessGroupRunning {
            process.signalProcessGroup(SIGKILL)
        }
        process.waitUntilExit()
    }
}
