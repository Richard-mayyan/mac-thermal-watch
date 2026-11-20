import Darwin
import Foundation
import MacThermalWatchCore

private struct Options {
    var interval: TimeInterval = 5
    var cpuThreshold: Double = 80
    var consecutiveSamples = 3
    var topProcessCount = 8
    var runOnce = false
    var notifications = false
    var jsonOutput = false
    var logPath: String? = "~/Library/Logs/MacThermalWatch/events.jsonl"
}

private enum CLIError: Error, CustomStringConvertible {
    case invalidOption(String)

    var description: String {
        switch self {
        case .invalidOption(let message): message
        }
    }
}

private let help = """
MacThermalWatch — diagnostic thermique local pour macOS
Développé par Richard BATHIEBO

USAGE
  macthermalwatch [options]

OPTIONS
  --once                 Une seule mesure puis arrêt
  --interval SECONDES    Intervalle entre mesures (défaut : 5)
  --cpu-threshold N      Seuil CPU par processus en % (défaut : 80)
  --consecutive N        Mesures consécutives avant alerte (défaut : 3)
  --top N                Nombre de processus affichés (défaut : 8)
  --notify               Active les notifications macOS
  --json                 Sortie JSON, une observation par ligne
  --log CHEMIN           Chemin du journal d'incidents JSONL
  --no-log               Désactive le journal d'incidents
  --help                 Affiche cette aide

EXEMPLES
  macthermalwatch --once
  macthermalwatch --notify --interval 5
  macthermalwatch --cpu-threshold 120 --consecutive 4

Un processus peut dépasser 100% sur un Mac multicœur. L'outil n'arrête jamais
un processus et ne désactive jamais les protections thermiques de macOS.
"""

private func parseOptions(_ arguments: [String]) throws -> Options {
    var options = Options()
    var index = 0

    func value(after option: String) throws -> String {
        guard index + 1 < arguments.count else {
            throw CLIError.invalidOption("Valeur manquante après \(option).")
        }
        index += 1
        return arguments[index]
    }

    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--once": options.runOnce = true
        case "--notify": options.notifications = true
        case "--json": options.jsonOutput = true
        case "--no-log": options.logPath = nil
        case "--interval":
            let raw = try value(after: argument)
            guard let value = Double(raw), value >= 1 else {
                throw CLIError.invalidOption("--interval doit être supérieur ou égal à 1.")
            }
            options.interval = value
        case "--cpu-threshold":
            let raw = try value(after: argument)
            guard let value = Double(raw), value > 0 else {
                throw CLIError.invalidOption("--cpu-threshold doit être positif.")
            }
            options.cpuThreshold = value
        case "--consecutive":
            let raw = try value(after: argument)
            guard let value = Int(raw), value > 0 else {
                throw CLIError.invalidOption("--consecutive doit être un entier positif.")
            }
            options.consecutiveSamples = value
        case "--top":
            let raw = try value(after: argument)
            guard let value = Int(raw), value > 0, value <= 50 else {
                throw CLIError.invalidOption("--top doit être compris entre 1 et 50.")
            }
            options.topProcessCount = value
        case "--log": options.logPath = try value(after: argument)
        case "--help", "-h":
            print(help)
            exit(EXIT_SUCCESS)
        default:
            throw CLIError.invalidOption("Option inconnue : \(argument)")
        }
        index += 1
    }
    return options
}

private func expandedPath(_ path: String) -> String {
    NSString(string: path).expandingTildeInPath
}

private final class IncidentLogger {
    private let fileURL: URL
    private let encoder: JSONEncoder

    init(path: String) throws {
        fileURL = URL(fileURLWithPath: expandedPath(path))
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    func append(_ observation: Observation) throws {
        var data = try encoder.encode(observation)
        data.append(0x0A)
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}

private final class NotificationSender {
    private var lastSent: [String: Date] = [:]
    private let cooldown: TimeInterval = 300

    func send(_ alert: MonitorAlert) {
        let key = "\(alert.kind.rawValue):\(alert.processID ?? 0)"
        if let date = lastSent[key], Date().timeIntervalSince(date) < cooldown { return }
        lastSent[key] = Date()

        let script = "display notification \(appleScriptString(alert.message)) with title \(appleScriptString("MacThermalWatch")) subtitle \(appleScriptString(alert.title))"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(escaped)\""
    }
}

private func format(_ observation: Observation) -> String {
    let snapshot = observation.snapshot
    let formatter = ISO8601DateFormatter()
    var lines: [String] = []
    let speed = snapshot.limits.speedPercent.map { "\($0)%" } ?? "n/d"
    let scheduler = snapshot.limits.schedulerPercent.map { "\($0)%" } ?? "n/d"
    let available = snapshot.limits.availableCPUs.map(String.init) ?? "n/d"
    let load = snapshot.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: " / ")

    lines.append("\n[\(formatter.string(from: snapshot.date))] \(snapshot.architecture)")
    lines.append("Thermique: \(snapshot.thermalLevel.rawValue.uppercased()) | vitesse CPU: \(speed) | ordonnanceur: \(scheduler) | CPU disponibles: \(available)/\(snapshot.processorCount) | charge: \(load)")
    lines.append(" PID     CPU%   MEM%  DURÉE       COMMANDE")
    for process in snapshot.topProcesses {
        lines.append(String(
            format: "%6d %7.1f %6.1f  %-11@ %@",
            process.pid,
            process.cpuPercent,
            process.memoryPercent,
            process.elapsed as NSString,
            process.command
        ))
    }

    for alert in observation.alerts {
        lines.append("⚠️  \(alert.title) — \(alert.message)")
    }

    if !snapshot.limits.hasValues, let note = snapshot.probeNotes.first {
        lines.append("ℹ️  Limites Intel indisponibles : \(note)")
    }
    return lines.joined(separator: "\n")
}

private func jsonLine(_ observation: Observation) throws -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(observation), as: UTF8.self)
}

do {
    let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
    let probe = SystemProbe()
    let detector = AnomalyDetector(
        cpuThreshold: options.cpuThreshold,
        requiredConsecutiveSamples: options.consecutiveSamples
    )
    let notifier = NotificationSender()
    let logger: IncidentLogger?
    if let path = options.logPath {
        logger = try IncidentLogger(path: path)
    } else {
        logger = nil
    }

    while true {
        let snapshot = probe.snapshot(topProcessCount: options.topProcessCount)
        let observation = Observation(snapshot: snapshot, alerts: detector.analyze(snapshot))

        if options.jsonOutput {
            print(try jsonLine(observation))
        } else {
            print(format(observation))
        }

        if !observation.alerts.isEmpty {
            try logger?.append(observation)
            if options.notifications {
                observation.alerts.forEach(notifier.send)
            }
        }

        if options.runOnce { break }
        Thread.sleep(forTimeInterval: options.interval)
    }
} catch {
    FileHandle.standardError.write(Data("Erreur : \(error)\n\n\(help)\n".utf8))
    exit(EXIT_FAILURE)
}
