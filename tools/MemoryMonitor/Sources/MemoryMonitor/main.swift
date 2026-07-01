// MemoryMonitor
//
// External memory recorder for DICOM viewer benchmarks.
// Samples target macOS processes with proc_pid_rusage and periodically
// supplements the sample with /usr/bin/footprint breakdowns.
//
// Licensed under the MIT License. See ../../LICENSE for details.

import Darwin
import Foundation

private let csvHeader = "timestamp,elapsed_s,process,pid,trial,footprint_mb,resident_mb,peak_footprint_mb,dirty_mb,swapped_mb,clean_mb,memory_pressure"

private struct Options {
    var processNames: [String] = []
    var interval: TimeInterval = 0.5
    var outputPath: String?
    var detailedEvery: Int = 10
}

private struct ProcessSample {
    let pid: pid_t
    let name: String
    let footprintMB: Double
    let residentMB: Double
    let peakFootprintMB: Double
}

private struct FootprintBreakdown {
    let dirtyMB: Double
    let swappedMB: Double
    let cleanMB: Double
}

private final class CSVWriter {
    private let handle: FileHandle?
    private let shouldClose: Bool

    init(path: String?) throws {
        guard let path else {
            self.handle = FileHandle.standardOutput
            self.shouldClose = false
            return
        }

        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: url.path, contents: nil)
        self.handle = try FileHandle(forWritingTo: url)
        self.shouldClose = true
    }

    deinit {
        if shouldClose {
            try? handle?.close()
        }
    }

    func writeLine(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        handle?.write(data)
    }
}

private func printUsage() {
    print("""
MemoryMonitor - External memory recorder for DICOM viewer benchmarks

Usage:
  MemoryMonitor --process <name> [--process <name2>] [options]

Options:
  --process, -p <name>    Process name to monitor (repeatable)
  --interval, -i <sec>    Sampling interval in seconds (default: 0.5)
  --output, -o <path>     Output CSV path (default: stdout)
  --detailed-every <N>    Run detailed footprint every N samples (default: 10)
  --help, -h              Show this help

Examples:
  MemoryMonitor -p OpenDicomViewer -p Horos -p OsiriX
  MemoryMonitor -p OpenDicomViewer -i 1.0

Runs continuously until Ctrl+C. Automatically detects app launches/quits
and tracks trial numbers (open app 3x = trials 1, 2, 3).
Output CSV is auto-timestamped when a directory is passed to --output.
""")
}

private func parseOptions(_ arguments: [String]) throws -> Options {
    var options = Options()
    var index = 1

    func requireValue(after flag: String) throws -> String {
        guard index + 1 < arguments.count else {
            throw RuntimeError("Missing value after \(flag)")
        }
        index += 1
        return arguments[index]
    }

    while index < arguments.count {
        let arg = arguments[index]
        switch arg {
        case "--help", "-h":
            printUsage()
            exit(0)
        case "--process", "-p":
            let value = try requireValue(after: arg)
            options.processNames.append(value)
        case "--interval", "-i":
            let value = try requireValue(after: arg)
            guard let interval = Double(value), interval > 0 else {
                throw RuntimeError("Invalid interval: \(value)")
            }
            options.interval = interval
        case "--output", "-o":
            options.outputPath = try requireValue(after: arg)
        case "--detailed-every":
            let value = try requireValue(after: arg)
            guard let count = Int(value), count > 0 else {
                throw RuntimeError("Invalid detailed sample interval: \(value)")
            }
            options.detailedEvery = count
        default:
            throw RuntimeError("Unknown option: \(arg)")
        }
        index += 1
    }

    guard !options.processNames.isEmpty else {
        throw RuntimeError("At least one --process name is required")
    }

    if let outputPath = options.outputPath, isDirectory(outputPath) {
        options.outputPath = URL(fileURLWithPath: outputPath)
            .appendingPathComponent("memory_benchmark_\(timestampForFilename()).csv")
            .path
    }

    return options
}

private func isDirectory(_ path: String) -> Bool {
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
}

private func timestampForFilename() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    return formatter.string(from: Date())
}

private func isoTimestamp() -> String {
    ISO8601DateFormatter().string(from: Date())
}

private func processName(pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: Int(MAXCOMLEN))
    let length = proc_name(pid, &buffer, UInt32(buffer.count))
    guard length > 0 else { return nil }
    return String(cString: buffer)
}

private func processPath(pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 4096)
    let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard length > 0 else { return nil }
    return String(cString: buffer)
}

private func pidsMatching(processNames: [String]) -> [(pid: pid_t, name: String)] {
    let bytesNeeded = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
    guard bytesNeeded > 0 else { return [] }

    let count = Int(bytesNeeded) / MemoryLayout<pid_t>.stride
    var pids = [pid_t](repeating: 0, count: count)
    let bytesWritten = proc_listpids(
        UInt32(PROC_ALL_PIDS),
        0,
        &pids,
        Int32(pids.count * MemoryLayout<pid_t>.stride)
    )
    guard bytesWritten > 0 else { return [] }

    let requested = Set(processNames)
    var matches: [(pid: pid_t, name: String)] = []

    for pid in pids where pid > 0 {
        guard let name = processName(pid: pid) else { continue }
        let pathName = processPath(pid: pid).map { URL(fileURLWithPath: $0).lastPathComponent }
        if requested.contains(name) || pathName.map(requested.contains) == true {
            matches.append((pid, name))
        }
    }

    return matches.sorted { lhs, rhs in
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.pid < rhs.pid
    }
}

private func sampleProcess(pid: pid_t, name: String) -> ProcessSample? {
    var info = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &info) { infoPtr -> Int32 in
        var rawInfo: rusage_info_t? = UnsafeMutableRawPointer(infoPtr)
        return withUnsafeMutablePointer(to: &rawInfo) {
            proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
        }
    }
    guard result == 0 else { return nil }

    let oneMB = 1024.0 * 1024.0
    return ProcessSample(
        pid: pid,
        name: name,
        footprintMB: Double(info.ri_phys_footprint) / oneMB,
        residentMB: Double(info.ri_resident_size) / oneMB,
        peakFootprintMB: Double(info.ri_lifetime_max_phys_footprint) / oneMB
    )
}

private func memoryPressureLevel() -> String {
    var level: Int32 = 0
    var size = MemoryLayout<Int32>.size
    let result = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
    guard result == 0 else { return "unknown" }

    switch level {
    case 0:
        return "normal"
    case 1:
        return "warning"
    case 2:
        return "critical"
    default:
        return "level-\(level)"
    }
}

private func runFootprint(pid: pid_t) -> FootprintBreakdown? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/footprint")
    process.arguments = ["-pid", "\(pid)"]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return nil
    }

    guard process.terminationStatus == 0 else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return nil }
    return parseFootprintSummary(output)
}

private func parseFootprintSummary(_ output: String) -> FootprintBreakdown? {
    for line in output.components(separatedBy: .newlines).reversed() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix("TOTAL") else { continue }
        let fields = trimmed.split(separator: " ").map(String.init)
        let totalIndex = fields.firstIndex(of: "TOTAL") ?? fields.count
        let sizeTokens = Array(fields[..<totalIndex])
        guard sizeTokens.count >= 4 else { return nil }

        let dirty = parseFootprintSize(sizeTokens[0], sizeTokens[1])
        let clean = parseFootprintSize(sizeTokens[2], sizeTokens[3])
        return FootprintBreakdown(
            dirtyMB: dirty,
            swappedMB: 0,
            cleanMB: clean
        )
    }
    return nil
}

private func parseFootprintSize(_ value: String, _ unit: String) -> Double {
    guard let number = Double(value) else { return 0 }
    switch unit.uppercased() {
    case "B":
        return number / 1_048_576.0
    case "KB", "K":
        return number / 1024.0
    case "MB", "M":
        return number
    case "GB", "G":
        return number * 1024.0
    default:
        return number
    }
}

private func format(_ value: Double) -> String {
    String(format: "%.1f", value)
}

private struct RuntimeError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private func run() throws {
    let options = try parseOptions(CommandLine.arguments)
    let writer = try CSVWriter(path: options.outputPath)

    if let outputPath = options.outputPath {
        print("Recording to: \(outputPath)")
    }
    print("Monitoring: \(options.processNames.joined(separator: ", "))")
    print("Runs continuously - open/close/reopen apps as needed.")
    print("Press Ctrl+C to stop when all trials are done.")
    print("")

    writer.writeLine(csvHeader)

    let start = Date()
    var sampleIndex = 0
    var trialCounter: [String: Int] = [:]
    var activeTrials: [pid_t: Int] = [:]
    var activeNames: [pid_t: String] = [:]
    var lastBreakdown: [pid_t: FootprintBreakdown] = [:]

    while true {
        sampleIndex += 1
        let found = pidsMatching(processNames: options.processNames)
        let currentPids = Set(found.map(\.pid))

        for (pid, name) in found {
            if activeTrials[pid] == nil {
                let nextTrial = (trialCounter[name] ?? 0) + 1
                trialCounter[name] = nextTrial
                activeTrials[pid] = nextTrial
                activeNames[pid] = name
                print("  -> \(name) detected (pid \(pid), trial \(nextTrial))")
            }
        }

        for pid in Array(activeTrials.keys) where !currentPids.contains(pid) {
            let name = activeNames[pid] ?? "process"
            let trial = activeTrials[pid] ?? 0
            print("  OK \(name) closed (trial \(trial) complete)")
            activeTrials[pid] = nil
            activeNames[pid] = nil
            lastBreakdown[pid] = nil
        }

        let pressure = memoryPressureLevel()
        for (pid, name) in found {
            guard let sample = sampleProcess(pid: pid, name: name),
                  let trial = activeTrials[pid] else {
                continue
            }

            let shouldRefreshBreakdown = sampleIndex == 1 || sampleIndex % options.detailedEvery == 0 || lastBreakdown[pid] == nil
            if shouldRefreshBreakdown, let breakdown = runFootprint(pid: pid) {
                lastBreakdown[pid] = breakdown
            }
            let breakdown = lastBreakdown[pid] ?? FootprintBreakdown(
                dirtyMB: sample.footprintMB,
                swappedMB: 0,
                cleanMB: max(0, sample.residentMB - sample.footprintMB)
            )

            let elapsed = Date().timeIntervalSince(start)
            writer.writeLine([
                isoTimestamp(),
                format(elapsed),
                sample.name,
                "\(sample.pid)",
                "\(trial)",
                format(sample.footprintMB),
                format(sample.residentMB),
                format(sample.peakFootprintMB),
                format(breakdown.dirtyMB),
                format(breakdown.swappedMB),
                format(breakdown.cleanMB),
                pressure
            ].joined(separator: ","))

            if shouldRefreshBreakdown {
                print("[\(String(format: "%6.1fs", elapsed))] \(sample.name) #\(trial) (pid \(sample.pid)): footprint=\(Int(sample.footprintMB.rounded()))MB peak=\(Int(sample.peakFootprintMB.rounded()))MB pressure=\(pressure) dirty=\(Int(breakdown.dirtyMB.rounded()))MB clean=\(Int(breakdown.cleanMB.rounded()))MB")
            }
        }

        Thread.sleep(forTimeInterval: options.interval)
    }
}

do {
    try run()
} catch let error as RuntimeError {
    fputs("MemoryMonitor: \(error.description)\n\n", stderr)
    printUsage()
    exit(2)
} catch {
    fputs("MemoryMonitor: \(error)\n", stderr)
    exit(1)
}
