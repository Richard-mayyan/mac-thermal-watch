import Darwin
import Foundation

public struct CommandResult: Sendable {
    public let status: Int32
    public let standardOutput: String
    public let standardError: String
}

public enum CommandError: Error, CustomStringConvertible {
    case launchFailed(String)

    public var description: String {
        switch self {
        case .launchFailed(let message): message
        }
    }
}

public struct CommandRunner: Sendable {
    public init() {}

    public func run(_ executable: String, arguments: [String]) throws -> CommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C"]) { _, new in new }

        do {
            try process.run()
        } catch {
            throw CommandError.launchFailed("\(executable): \(error.localizedDescription)")
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return CommandResult(
            status: process.terminationStatus,
            standardOutput: String(decoding: outputData, as: UTF8.self),
            standardError: String(decoding: errorData, as: UTF8.self)
        )
    }
}

public final class SystemProbe {
    private let runner: CommandRunner
    private let architecture: String

    public init(runner: CommandRunner = CommandRunner()) {
        self.runner = runner
        self.architecture = (try? runner.run("/usr/bin/uname", arguments: ["-m"]).standardOutput)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? "unknown"
    }

    public func snapshot(topProcessCount: Int) -> SystemSnapshot {
        var notes: [String] = []
        let limits = readThermalLimits(notes: &notes)
        let processes = readProcesses(notes: &notes)
            .filter { $0.pid != ProcessInfo.processInfo.processIdentifier }
            .sorted {
                if $0.cpuPercent == $1.cpuPercent { return $0.pid < $1.pid }
                return $0.cpuPercent > $1.cpuPercent
            }

        return SystemSnapshot(
            date: Date(),
            thermalLevel: currentThermalLevel(),
            limits: limits,
            loadAverage: loadAverage(),
            processorCount: ProcessInfo.processInfo.processorCount,
            activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount,
            architecture: architecture,
            topProcesses: Array(processes.prefix(max(1, topProcessCount))),
            probeNotes: notes
        )
    }

    private func readThermalLimits(notes: inout [String]) -> ThermalLimits {
        do {
            let result = try runner.run("/usr/bin/pmset", arguments: ["-g", "therm"])
            let limits = Parsers.thermalLimits(from: result.standardOutput)
            if !limits.hasValues {
                let detail = result.standardError
                    .split(whereSeparator: \.isNewline)
                    .first
                    .map(String.init)
                notes.append(detail ?? "pmset ne fournit pas de limites CPU sur ce Mac.")
            }
            return limits
        } catch {
            notes.append("Lecture pmset impossible : \(error)")
            return ThermalLimits(schedulerPercent: nil, availableCPUs: nil, speedPercent: nil)
        }
    }

    private func readProcesses(notes: inout [String]) -> [ProcessUsage] {
        do {
            let result = try runner.run(
                "/bin/ps",
                arguments: ["-axo", "pid=,pcpu=,pmem=,etime=,comm="]
            )
            guard result.status == 0 else {
                notes.append("ps a terminé avec le code \(result.status).")
                return []
            }
            return Parsers.processes(from: result.standardOutput)
        } catch {
            notes.append("Lecture des processus impossible : \(error)")
            return []
        }
    }

    private func currentThermalLevel() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .unknown
        }
    }

    private func loadAverage() -> [Double] {
        var values = [Double](repeating: 0, count: 3)
        let count = values.withUnsafeMutableBufferPointer { buffer in
            getloadavg(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return [] }
        return Array(values.prefix(Int(count)))
    }
}
