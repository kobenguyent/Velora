import Darwin
import Foundation

private final class SupervisorDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func set(_ newValue: Data) {
        lock.lock()
        data = newValue
        lock.unlock()
    }

    func get() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

private final class SupervisorBoolBox: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    func setTrue() {
        lock.lock()
        flag = true
        lock.unlock()
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }
}

/// Safe subprocess configuration, process-group lifecycle management, and deadlock-free pipe collection.
public enum ProcessSupervisor {

    public static func configure(
        _ process: Process,
        executableURL: URL,
        arguments: [String],
        environment: [String: String]
    ) {
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
    }

    public static func launchInNewProcessGroup(_ process: Process) throws -> pid_t {
        try process.run()
        let pid = process.processIdentifier
        if pid > 0 {
            _ = Darwin.setpgid(pid, pid)
        }
        return pid
    }

    public static func terminateProcessGroup(
        pid: pid_t,
        process: Process,
        graceSeconds: Double = 2.0
    ) {
        if pid > 0 {
            _ = Darwin.kill(-pid, SIGTERM)
        }
        if process.isRunning {
            process.terminate()
        }

        let delay = max(0.05, graceSeconds)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
            guard process.isRunning else { return }
            if pid > 0 {
                _ = Darwin.kill(-pid, SIGKILL)
            }
            if process.isRunning {
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    public static func runCollectingOutput(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeoutSeconds: Double = 15
    ) async -> (exitCode: Int32, stdout: Data, stderr: Data, timedOut: Bool) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                configure(
                    process,
                    executableURL: URL(fileURLWithPath: executable),
                    arguments: arguments,
                    environment: environment
                )

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let pid: pid_t
                do {
                    pid = try launchInNewProcessGroup(process)
                } catch {
                    continuation.resume(returning: (-1, Data(), Data(), false))
                    return
                }

                let timedOutBox = SupervisorBoolBox()
                let timeoutWork = DispatchWorkItem {
                    if process.isRunning {
                        timedOutBox.setTrue()
                        terminateProcessGroup(pid: pid, process: process, graceSeconds: 0.5)
                    }
                }
                DispatchQueue.global(qos: .utility).asyncAfter(
                    deadline: .now() + max(0.05, timeoutSeconds),
                    execute: timeoutWork
                )

                let outBox = SupervisorDataBox()
                let errBox = SupervisorDataBox()
                let ioGroup = DispatchGroup()

                ioGroup.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    outBox.set(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
                    ioGroup.leave()
                }

                ioGroup.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    errBox.set(stderrPipe.fileHandleForReading.readDataToEndOfFile())
                    ioGroup.leave()
                }

                process.waitUntilExit()
                timeoutWork.cancel()
                ioGroup.wait()

                continuation.resume(returning: (
                    process.terminationStatus,
                    outBox.get(),
                    errBox.get(),
                    timedOutBox.value
                ))
            }
        }
    }
}
