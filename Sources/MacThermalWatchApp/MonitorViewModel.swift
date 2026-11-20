import AppKit
import Foundation
import MacThermalWatchCore

struct TimedAlert: Identifiable {
    let id = UUID()
    let date: Date
    let alert: MonitorAlert
}

struct ApplicationActionRequest: Identifiable {
    enum Kind {
        case quit
        case forceQuit
    }

    let id = UUID()
    let process: ProcessUsage
    let applicationName: String
    let kind: Kind
}

struct ActionFeedback: Identifiable {
    let id = UUID()
    let message: String
    let isError: Bool
}

private final class SamplingWorker: @unchecked Sendable {
    private let probe = SystemProbe()
    private let detector = AnomalyDetector(cpuThreshold: 80, requiredConsecutiveSamples: 3)

    func sample() -> (SystemSnapshot, [MonitorAlert]) {
        let snapshot = probe.snapshot(topProcessCount: 10)
        return (snapshot, detector.analyze(snapshot))
    }
}

enum MachineHealth {
    case waiting
    case normal
    case attention
    case danger

    var title: String {
        switch self {
        case .waiting: "En attente de la première mesure"
        case .normal: "Le Mac fonctionne normalement"
        case .attention: "Le Mac commence à être limité"
        case .danger: "Refroidissement insuffisant"
        }
    }

    var detail: String {
        switch self {
        case .waiting:
            "La première analyse prend généralement quelques secondes."
        case .normal:
            "Aucune pression thermique importante ni limitation CPU détectée."
        case .attention:
            "macOS réduit légèrement les performances. Surveillez les applications les plus actives."
        case .danger:
            "macOS bride fortement le processeur pour protéger le matériel. Laissez la machine refroidir."
        }
    }

    var symbol: String {
        switch self {
        case .waiting: "hourglass"
        case .normal: "checkmark.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .danger: "thermometer.sun.fill"
        }
    }
}

@MainActor
final class MonitorViewModel: ObservableObject {
    @Published private(set) var snapshot: SystemSnapshot?
    @Published private(set) var alerts: [TimedAlert] = []
    @Published private(set) var speedHistory: [Double] = []
    @Published private(set) var loadHistory: [Double] = []
    @Published private(set) var isRunning = false
    @Published private(set) var isSampling = false
    @Published var interval: TimeInterval = 5
    @Published var pendingAction: ApplicationActionRequest?
    @Published private(set) var feedback: ActionFeedback?

    private let worker = SamplingWorker()
    private let samplingQueue = DispatchQueue(label: "com.richardbathiebo.macthermalwatch.sampling", qos: .utility)
    private var timer: Timer?
    private var lastAlertDates: [String: Date] = [:]

    var health: MachineHealth {
        guard let snapshot else { return .waiting }
        let speed = snapshot.limits.speedPercent ?? 100
        let scheduler = snapshot.limits.schedulerPercent ?? 100
        let load = snapshot.loadAverage.first ?? 0
        let highLoad = load > Double(max(1, snapshot.activeProcessorCount)) * 2

        if snapshot.thermalLevel.rank >= ThermalLevel.serious.rank || speed < 60 || scheduler < 60 {
            return .danger
        }
        if snapshot.thermalLevel == .fair || speed < 90 || scheduler < 90 || highLoad {
            return .attention
        }
        return .normal
    }

    var recommendation: String {
        guard let snapshot else { return "Démarrez la surveillance pour obtenir un diagnostic." }
        let speed = snapshot.limits.speedPercent ?? 100

        if health == .danger {
            let process = snapshot.topProcesses.first.map(friendlyProcessName)
            if let process {
                return "Mettez en pause la tâche dans \(process), posez le Mac sur une surface dure et laissez-le refroidir. Si le ventilateur n’accélère pas, lancez Apple Diagnostics."
            }
            return "Laissez le Mac refroidir sur une surface dure. Si le ventilateur n’accélère pas, lancez Apple Diagnostics."
        }
        if speed < 90 {
            return "Une limitation CPU est active. Évitez de démarrer une nouvelle tâche lourde jusqu’au retour à 100 %."
        }
        if snapshot.thermalLevel == .fair {
            return "La température monte. Vérifiez que les aérations sont libres et surveillez les processus ci-dessous."
        }
        return "Aucune action nécessaire. Vous pouvez laisser la surveillance active pendant votre utilisation normale."
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        scheduleTimer()
        refresh()
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func toggleMonitoring() {
        isRunning ? stop() : start()
    }

    func updateInterval(_ value: TimeInterval) {
        interval = value
        if isRunning { scheduleTimer() }
    }

    func refresh() {
        guard !isSampling else { return }
        isSampling = true
        let worker = self.worker

        samplingQueue.async { [weak self] in
            let (snapshot, detectedAlerts) = worker.sample()

            DispatchQueue.main.async { [weak self] in
                self?.receive(snapshot: snapshot, alerts: detectedAlerts)
            }
        }
    }

    func revealLog() {
        let url = Self.logURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    func canQuit(_ process: ProcessUsage) -> Bool {
        managedApplication(for: process) != nil
    }

    func requestQuit(_ process: ProcessUsage, force: Bool = false) {
        guard let application = managedApplication(for: process) else {
            showFeedback("Ce processus système ne peut pas être fermé depuis MacThermalWatch.", isError: true)
            return
        }
        pendingAction = ApplicationActionRequest(
            process: process,
            applicationName: application.localizedName ?? friendlyProcessName(process),
            kind: force ? .forceQuit : .quit
        )
    }

    func confirm(_ request: ApplicationActionRequest) {
        guard let application = managedApplication(for: request.process) else {
            showFeedback("L’application n’est plus active ou ne peut pas être gérée.", isError: true)
            return
        }

        let accepted: Bool
        switch request.kind {
        case .quit:
            accepted = application.terminate()
        case .forceQuit:
            accepted = application.forceTerminate()
        }

        if accepted {
            let wording = request.kind == .forceQuit ? "Fermeture forcée envoyée" : "Demande de fermeture envoyée"
            showFeedback("\(wording) à \(request.applicationName).", isError: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.refresh()
            }
        } else {
            showFeedback("macOS n’a pas accepté la demande pour \(request.applicationName).", isError: true)
        }
    }

    var manageableProcesses: [ProcessUsage] {
        guard let processes = snapshot?.topProcesses else { return [] }
        var seenBundles = Set<String>()
        return processes.filter { process in
            guard let application = managedApplication(for: process),
                  let bundlePath = application.bundleURL?.standardizedFileURL.path,
                  seenBundles.insert(bundlePath).inserted else {
                return false
            }
            return true
        }
    }

    func friendlyProcessName(_ process: ProcessUsage) -> String {
        let command = process.command
        if command.contains("Google Chrome Helper") {
            return command.contains("Renderer") ? "Google Chrome — page ou Meet" : "Google Chrome — service"
        }
        if command.contains("WindowServer") { return "macOS — affichage (WindowServer)" }
        if command.contains("coreaudiod") { return "macOS — audio" }

        if let appRange = command.range(of: "/Applications/"),
           let suffix = command[appRange.upperBound...].split(separator: "/").first {
            return String(suffix).replacingOccurrences(of: ".app", with: "")
        }
        return URL(fileURLWithPath: command).lastPathComponent
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func receive(snapshot: SystemSnapshot, alerts detectedAlerts: [MonitorAlert]) {
        self.snapshot = snapshot
        isSampling = false

        let speed = Double(snapshot.limits.speedPercent ?? 100)
        speedHistory.append(speed)
        loadHistory.append(snapshot.loadAverage.first ?? 0)
        speedHistory = Array(speedHistory.suffix(60))
        loadHistory = Array(loadHistory.suffix(60))

        let now = Date()
        for alert in detectedAlerts {
            let key = "\(alert.kind.rawValue):\(alert.processID ?? 0)"
            if let lastDate = lastAlertDates[key], now.timeIntervalSince(lastDate) < 60 { continue }
            lastAlertDates[key] = now
            alerts.insert(TimedAlert(date: now, alert: alert), at: 0)
        }
        alerts = Array(alerts.prefix(30))

        if !detectedAlerts.isEmpty {
            appendToLog(Observation(snapshot: snapshot, alerts: detectedAlerts))
        }
    }

    private func appendToLog(_ observation: Observation) {
        do {
            let url = Self.logURL
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            var data = try encoder.encode(observation)
            data.append(0x0A)

            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // La surveillance doit continuer même si le journal n'est pas inscriptible.
        }
    }

    private func managedApplication(for process: ProcessUsage) -> NSRunningApplication? {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        guard process.pid != currentPID else { return nil }

        if let direct = NSRunningApplication(processIdentifier: process.pid),
           isAllowedToQuit(direct) {
            return direct
        }

        guard let bundlePath = Parsers.applicationBundlePath(from: process.command) else {
            return nil
        }
        let bundleURL = URL(fileURLWithPath: bundlePath).standardizedFileURL
        return NSWorkspace.shared.runningApplications.first { application in
            application.bundleURL?.standardizedFileURL == bundleURL && isAllowedToQuit(application)
        }
    }

    private func isAllowedToQuit(_ application: NSRunningApplication) -> Bool {
        guard !application.isTerminated,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              application.activationPolicy == .regular,
              let path = application.bundleURL?.standardizedFileURL.path else {
            return false
        }

        let userApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications")
            .standardizedFileURL.path + "/"
        let isUserApplication = path.hasPrefix("/Applications/") || path.hasPrefix(userApplications)
        let isThisApp = application.bundleIdentifier == "com.richardbathiebo.MacThermalWatch"
        return isUserApplication && !isThisApp
    }

    private func showFeedback(_ message: String, isError: Bool) {
        let value = ActionFeedback(message: message, isError: isError)
        feedback = value
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard self?.feedback?.id == value.id else { return }
            self?.feedback = nil
        }
    }

    private static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MacThermalWatch/events.jsonl")
    }
}
