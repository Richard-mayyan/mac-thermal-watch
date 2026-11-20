import XCTest
@testable import MacThermalWatchCore

final class ParserTests: XCTestCase {
    func testParsesIntelThermalLimits() {
        let output = """
        Note: No thermal warning level has been recorded
        Note: No performance warning level has been recorded
        CPU_Scheduler_Limit = 72
        CPU_Available_CPUs = 6
        CPU_Speed_Limit = 58
        """

        XCTAssertEqual(
            Parsers.thermalLimits(from: output),
            ThermalLimits(schedulerPercent: 72, availableCPUs: 6, speedPercent: 58)
        )
    }

    func testParsesProcessesAndPreservesCommandSpaces() {
        let output = """
          101  97.5  2.4  01:23:45 /Applications/Video Editor.app/Contents/MacOS/Video Editor
          202   3.1  0.8     04:02 /System/Library/CoreServices/Finder.app/Contents/MacOS/Finder
        """

        let processes = Parsers.processes(from: output)
        XCTAssertEqual(processes.count, 2)
        XCTAssertEqual(processes[0].pid, 101)
        XCTAssertEqual(processes[0].cpuPercent, 97.5)
        XCTAssertEqual(
            processes[0].command,
            "/Applications/Video Editor.app/Contents/MacOS/Video Editor"
        )
    }

    func testFindsRootApplicationBundleInsideHelperPath() {
        let command = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"

        XCTAssertEqual(
            Parsers.applicationBundlePath(from: command),
            "/Applications/Google Chrome.app"
        )
        XCTAssertNil(Parsers.applicationBundlePath(from: "/usr/libexec/secd"))
    }
}
