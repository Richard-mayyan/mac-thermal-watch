import Foundation

public final class AnomalyDetector {
    public let cpuThreshold: Double
    public let requiredConsecutiveSamples: Int

    private struct ProcessKey: Hashable {
        let pid: Int32
        let command: String
    }

    private var highCPUStreaks: [ProcessKey: Int] = [:]

    public init(cpuThreshold: Double = 80, requiredConsecutiveSamples: Int = 3) {
        self.cpuThreshold = cpuThreshold
        self.requiredConsecutiveSamples = max(1, requiredConsecutiveSamples)
    }

    public func analyze(_ snapshot: SystemSnapshot) -> [MonitorAlert] {
        var alerts: [MonitorAlert] = []

        if snapshot.thermalLevel.rank >= ThermalLevel.serious.rank {
            alerts.append(MonitorAlert(
                kind: .thermalPressure,
                severity: snapshot.thermalLevel == .critical ? 3 : 2,
                title: "Pression thermique \(snapshot.thermalLevel.rawValue)",
                message: "macOS réduit déjà les performances pour refroidir le Mac."
            ))
        }

        if let limit = snapshot.limits.speedPercent, limit < 90 {
            alerts.append(MonitorAlert(
                kind: .cpuSpeedLimited,
                severity: limit < 60 ? 3 : 2,
                title: "Vitesse CPU limitée à \(limit)%",
                message: "Une limitation thermique ou énergétique est active."
            ))
        }

        if let limit = snapshot.limits.schedulerPercent, limit < 90 {
            alerts.append(MonitorAlert(
                kind: .cpuSchedulerLimited,
                severity: limit < 60 ? 3 : 2,
                title: "Planificateur CPU limité à \(limit)%",
                message: "macOS réduit la capacité de calcul disponible."
            ))
        }

        if let available = snapshot.limits.availableCPUs,
           available < snapshot.processorCount {
            alerts.append(MonitorAlert(
                kind: .fewerCPUsAvailable,
                severity: 2,
                title: "Seulement \(available)/\(snapshot.processorCount) CPU disponibles",
                message: "macOS a désactivé temporairement une partie des cœurs logiques."
            ))
        }

        let currentKeys = Set(snapshot.topProcesses.map {
            ProcessKey(pid: $0.pid, command: $0.command)
        })
        highCPUStreaks = highCPUStreaks.filter { currentKeys.contains($0.key) }

        for process in snapshot.topProcesses {
            let key = ProcessKey(pid: process.pid, command: process.command)
            if process.cpuPercent >= cpuThreshold {
                let streak = highCPUStreaks[key, default: 0] + 1
                highCPUStreaks[key] = streak
                if streak == requiredConsecutiveSamples {
                    alerts.append(MonitorAlert(
                        kind: .sustainedHighCPU,
                        severity: 1,
                        title: "Processus durablement gourmand",
                        message: "\(process.command) (PID \(process.pid)) utilise \(String(format: "%.1f", process.cpuPercent))% CPU depuis \(streak) mesures.",
                        processID: process.pid
                    ))
                }
            } else {
                highCPUStreaks.removeValue(forKey: key)
            }
        }

        return alerts
    }
}
