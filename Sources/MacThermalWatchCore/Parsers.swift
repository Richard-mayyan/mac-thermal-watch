import Foundation

public enum Parsers {
    public static func thermalLimits(from output: String) -> ThermalLimits {
        var scheduler: Int?
        var availableCPUs: Int?
        var speed: Int?

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            let pair = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard pair.count == 2 else { continue }

            let value = firstInteger(in: pair[1])
            switch pair[0] {
            case "CPU_Scheduler_Limit": scheduler = value
            case "CPU_Available_CPUs": availableCPUs = value
            case "CPU_Speed_Limit": speed = value
            default: break
            }
        }

        return ThermalLimits(
            schedulerPercent: scheduler,
            availableCPUs: availableCPUs,
            speedPercent: speed
        )
    }

    public static func processes(from output: String) -> [ProcessUsage] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine in
                let fields = rawLine.split(
                    maxSplits: 4,
                    omittingEmptySubsequences: true,
                    whereSeparator: \.isWhitespace
                )
                guard fields.count == 5,
                      let pid = Int32(fields[0]),
                      let cpu = Double(fields[1]),
                      let memory = Double(fields[2]) else {
                    return nil
                }

                return ProcessUsage(
                    pid: pid,
                    cpuPercent: cpu,
                    memoryPercent: memory,
                    elapsed: String(fields[3]),
                    command: String(fields[4])
                )
            }
    }

    private static func firstInteger(in text: String) -> Int? {
        let digits = text.prefix { $0 == "-" || $0.isNumber }
        return Int(digits)
    }
}
