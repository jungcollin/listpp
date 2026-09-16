import Foundation

final class PortScanner {
    private struct ProcessMetadata {
        let commandLine: String
        let elapsedSeconds: Int?
    }

    private struct RawPortRecord {
        let command: String
        let pid: Int
        let user: String
        let endpoint: String
        let port: Int
    }

    private struct PortGroupKey: Hashable {
        let command: String
        let pid: Int
        let user: String
        let port: Int
        let serviceName: String?
    }

    private let serviceCatalog = ServiceCatalog()
    private let homeDirectory: String

    init(homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.homeDirectory = homeDirectory
    }

    func scanListeningTCPPorts(sortedBy sortMode: EntrySortMode) -> PortScanOutcome {
        guard let result = Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"]) else {
            return .failure("Failed to execute lsof.")
        }
        guard result.status == 0 else {
            let detail = result.stderr.isEmpty ? result.stdout : result.stderr
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(trimmed.isEmpty ? "lsof exited with status \(result.status)." : trimmed)
        }

        let lines = result.stdout.split(whereSeparator: \.isNewline)
        guard lines.count > 1 else {
            return .success([])
        }

        var grouped: [PortGroupKey: Set<String>] = [:]
        for line in lines.dropFirst() {
            guard let raw = parse(line: String(line)) else {
                continue
            }

            let serviceName = serviceCatalog.resolveServiceName(port: raw.port, command: raw.command)
            let key = PortGroupKey(
                command: raw.command,
                pid: raw.pid,
                user: raw.user,
                port: raw.port,
                serviceName: serviceName
            )

            grouped[key, default: []].insert(raw.endpoint)
        }

        let pids = Array(Set(grouped.keys.map(\.pid))).sorted()
        let processMetadata = fetchProcessMetadata(for: pids)
        let workingDirectories = fetchWorkingDirectories(for: pids)

        let entries = grouped.map { key, endpoints in
            let commandLine = processMetadata[key.pid]?.commandLine
            let identity = PortIdentity.resolve(
                command: key.command,
                commandLine: commandLine,
                workingDirectory: workingDirectories[key.pid],
                homeDirectory: homeDirectory
            )
            return PortEntry(
                command: key.command,
                pid: key.pid,
                user: key.user,
                port: key.port,
                serviceName: key.serviceName,
                endpoints: endpoints.sorted(),
                commandLine: commandLine,
                workingDirectory: identity.workingDirectory,
                projectLabel: identity.projectLabel,
                toolLabel: identity.toolLabel,
                isProjectServer: identity.isProjectServer
            )
        }

        switch sortMode {
        case .newest:
            return .success(entries.sorted { lhs, rhs in
                let lhsElapsed = processMetadata[lhs.pid]?.elapsedSeconds ?? Int.max
                let rhsElapsed = processMetadata[rhs.pid]?.elapsedSeconds ?? Int.max
                if lhsElapsed != rhsElapsed { return lhsElapsed < rhsElapsed }
                if lhs.port != rhs.port { return lhs.port < rhs.port }
                if lhs.command != rhs.command { return lhs.command < rhs.command }
                return lhs.pid < rhs.pid
            })
        case .port:
            return .success(entries.sorted { lhs, rhs in
                if lhs.port != rhs.port { return lhs.port < rhs.port }
                if lhs.command != rhs.command { return lhs.command < rhs.command }
                return lhs.pid < rhs.pid
            })
        }
    }

    private func parse(line: String) -> RawPortRecord? {
        let columns = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard columns.count >= 10 else { return nil }
        guard let pid = Int(columns[1]) else { return nil }

        let command = String(columns[0])
        let user = String(columns[2])
        var nameField = columns[8...].joined(separator: " ")

        if nameField.hasPrefix("TCP ") {
            nameField.removeFirst(4)
        }
        if nameField.hasSuffix(" (LISTEN)") {
            nameField.removeLast(" (LISTEN)".count)
        }

        guard let colon = nameField.lastIndex(of: ":") else { return nil }
        guard colon < nameField.index(before: nameField.endIndex) else { return nil }
        let portString = nameField[nameField.index(after: colon)...]
        guard let port = Int(portString) else { return nil }

        return RawPortRecord(
            command: command,
            pid: pid,
            user: user,
            endpoint: nameField,
            port: port
        )
    }

    private func fetchProcessMetadata(for pids: [Int]) -> [Int: ProcessMetadata] {
        guard !pids.isEmpty else { return [:] }
        let pidArg = pids.map(String.init).joined(separator: ",")

        guard let result = Shell.run("/bin/ps", ["-ww", "-o", "pid=", "-o", "etime=", "-o", "command=", "-p", pidArg]) else {
            return [:]
        }
        guard result.status == 0 else {
            return [:]
        }

        var map: [Int: ProcessMetadata] = [:]

        for rawLine in result.stdout.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                continue
            }

            let tokens = line.split(maxSplits: 2, whereSeparator: { $0 == " " || $0 == "\t" })
            guard tokens.count >= 2 else {
                continue
            }
            guard let pid = Int(tokens[0]) else {
                continue
            }
            let elapsedText = String(tokens[1])
            let commandLine = tokens.count == 3
                ? String(tokens[2]).trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            map[pid] = ProcessMetadata(
                commandLine: commandLine,
                elapsedSeconds: parseElapsedSeconds(elapsedText)
            )
        }

        return map
    }

    private func fetchWorkingDirectories(for pids: [Int]) -> [Int: String] {
        guard !pids.isEmpty else { return [:] }

        var directories: [Int: String] = [:]
        for batch in stride(from: 0, to: pids.count, by: 80) {
            let slice = pids[batch..<min(batch + 80, pids.count)]
            let pidArg = slice.map(String.init).joined(separator: ",")
            guard let result = Shell.run(
                "/usr/sbin/lsof",
                ["-nP", "-w", "-Fpn", "-a", "-d", "cwd", "-p", pidArg]
            ) else {
                continue
            }
            let parsed = PortIdentity.parseLsofCwdFields(result.stdout)
            for (pid, path) in parsed {
                directories[pid] = path
            }
        }
        return directories
    }

    private func parseElapsedSeconds(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var days = 0
        var timePart = trimmed
        if let dashIndex = trimmed.firstIndex(of: "-") {
            let dayText = trimmed[..<dashIndex]
            guard let parsedDays = Int(dayText) else { return nil }
            days = parsedDays
            timePart = String(trimmed[trimmed.index(after: dashIndex)...])
        }

        let fields = timePart.split(separator: ":")
        guard fields.count == 2 || fields.count == 3 else { return nil }

        func parseField(_ value: Substring) -> Int? {
            let numberPart = value.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)[0]
            return Int(numberPart)
        }

        if fields.count == 2 {
            guard
                let minutes = parseField(fields[0]),
                let seconds = parseField(fields[1])
            else { return nil }
            return (days * 24 * 60 * 60) + (minutes * 60) + seconds
        }

        guard
            let hours = parseField(fields[0]),
            let minutes = parseField(fields[1]),
            let seconds = parseField(fields[2])
        else { return nil }

        return (days * 24 * 60 * 60) + (hours * 60 * 60) + (minutes * 60) + seconds
    }
}
