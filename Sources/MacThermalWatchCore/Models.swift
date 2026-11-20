import Foundation

public enum ThermalLevel: String, Codable, Sendable, CaseIterable {
    case nominal
    case fair
    case serious
    case critical
    case unknown

    public var rank: Int {
        switch self {
        case .unknown: 0
        case .nominal: 1
        case .fair: 2
        case .serious: 3
        case .critical: 4
        }
    }
}

public struct ThermalLimits: Codable, Sendable, Equatable {
    public let schedulerPercent: Int?
    public let availableCPUs: Int?
    public let speedPercent: Int?

    public init(schedulerPercent: Int?, availableCPUs: Int?, speedPercent: Int?) {
        self.schedulerPercent = schedulerPercent
        self.availableCPUs = availableCPUs
        self.speedPercent = speedPercent
    }

    public var hasValues: Bool {
        schedulerPercent != nil || availableCPUs != nil || speedPercent != nil
    }
}

public struct ProcessUsage: Codable, Sendable, Equatable {
    public let pid: Int32
    public let cpuPercent: Double
    public let memoryPercent: Double
    public let elapsed: String
    public let command: String

    public init(
        pid: Int32,
        cpuPercent: Double,
        memoryPercent: Double,
        elapsed: String,
        command: String
    ) {
        self.pid = pid
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.elapsed = elapsed
        self.command = command
    }
}

public struct SystemSnapshot: Codable, Sendable {
    public let date: Date
    public let thermalLevel: ThermalLevel
    public let limits: ThermalLimits
    public let loadAverage: [Double]
    public let processorCount: Int
    public let activeProcessorCount: Int
    public let architecture: String
    public let topProcesses: [ProcessUsage]
    public let probeNotes: [String]

    public init(
        date: Date,
        thermalLevel: ThermalLevel,
        limits: ThermalLimits,
        loadAverage: [Double],
        processorCount: Int,
        activeProcessorCount: Int,
        architecture: String,
        topProcesses: [ProcessUsage],
        probeNotes: [String]
    ) {
        self.date = date
        self.thermalLevel = thermalLevel
        self.limits = limits
        self.loadAverage = loadAverage
        self.processorCount = processorCount
        self.activeProcessorCount = activeProcessorCount
        self.architecture = architecture
        self.topProcesses = topProcesses
        self.probeNotes = probeNotes
    }
}

public enum AlertKind: String, Codable, Sendable {
    case thermalPressure
    case cpuSpeedLimited
    case cpuSchedulerLimited
    case fewerCPUsAvailable
    case sustainedHighCPU
}

public struct MonitorAlert: Codable, Sendable, Equatable {
    public let kind: AlertKind
    public let severity: Int
    public let title: String
    public let message: String
    public let processID: Int32?

    public init(
        kind: AlertKind,
        severity: Int,
        title: String,
        message: String,
        processID: Int32? = nil
    ) {
        self.kind = kind
        self.severity = severity
        self.title = title
        self.message = message
        self.processID = processID
    }
}

public struct Observation: Codable, Sendable {
    public let snapshot: SystemSnapshot
    public let alerts: [MonitorAlert]

    public init(snapshot: SystemSnapshot, alerts: [MonitorAlert]) {
        self.snapshot = snapshot
        self.alerts = alerts
    }
}
