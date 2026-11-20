import XCTest
@testable import MacThermalWatchCore

final class AnomalyDetectorTests: XCTestCase {
    func testHighCPURequiresConsecutiveSamples() {
        let detector = AnomalyDetector(cpuThreshold: 80, requiredConsecutiveSamples: 3)
        let snapshot = makeSnapshot(cpu: 95)

        XCTAssertTrue(detector.analyze(snapshot).isEmpty)
        XCTAssertTrue(detector.analyze(snapshot).isEmpty)
        XCTAssertEqual(detector.analyze(snapshot).map(\.kind), [.sustainedHighCPU])
        XCTAssertTrue(detector.analyze(snapshot).isEmpty)
    }

    func testThermalAndSpeedLimitsTriggerImmediately() {
        let detector = AnomalyDetector()
        let snapshot = makeSnapshot(
            thermal: .serious,
            limits: ThermalLimits(schedulerPercent: 100, availableCPUs: 8, speedPercent: 55),
            cpu: 0
        )

        XCTAssertEqual(
            Set(detector.analyze(snapshot).map(\.kind)),
            Set([.thermalPressure, .cpuSpeedLimited])
        )
    }

    private func makeSnapshot(
        thermal: ThermalLevel = .nominal,
        limits: ThermalLimits = ThermalLimits(
            schedulerPercent: 100,
            availableCPUs: 8,
            speedPercent: 100
        ),
        cpu: Double
    ) -> SystemSnapshot {
        SystemSnapshot(
            date: Date(timeIntervalSince1970: 0),
            thermalLevel: thermal,
            limits: limits,
            loadAverage: [1, 1, 1],
            processorCount: 8,
            activeProcessorCount: 8,
            architecture: "x86_64",
            topProcesses: [
                ProcessUsage(
                    pid: 42,
                    cpuPercent: cpu,
                    memoryPercent: 1,
                    elapsed: "01:00",
                    command: "/Applications/Test.app/Contents/MacOS/Test"
                )
            ],
            probeNotes: []
        )
    }
}
