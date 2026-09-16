import Foundation

struct PortEntry: Hashable, Identifiable {
    var id: String { "\(pid):\(port):\(command):\(user)" }

    let command: String
    let pid: Int
    let user: String
    let port: Int
    let serviceName: String?
    let endpoints: [String]
    let commandLine: String?
    let workingDirectory: String?
    let projectLabel: String?
    let toolLabel: String?
    let isProjectServer: Bool

    var canRestart: Bool {
        guard let commandLine else { return false }
        return !commandLine.isEmpty
    }

    var displayTitle: String {
        identity.displayTitle(fallbackCommand: command)
    }

    var displayBadge: String? {
        toolLabel
    }

    var projectName: String? {
        identity.projectName
    }

    var projectBucket: String? {
        identity.projectBucket
    }

    var identityLine: String {
        var parts: [String] = []
        if let toolLabel, toolLabel.caseInsensitiveCompare(displayTitle) != .orderedSame {
            parts.append(toolLabel)
        }
        if command.caseInsensitiveCompare(displayTitle) != .orderedSame,
           command.caseInsensitiveCompare(toolLabel ?? "") != .orderedSame {
            parts.append(command)
        }
        parts.append("PID \(pid)")
        parts.append(user)
        return parts.joined(separator: "  ·  ")
    }

    func locationLine(homeDirectory: String) -> String? {
        guard let workingDirectory else { return nil }
        let compact = PortIdentity.compactPath(workingDirectory, homeDirectory: homeDirectory)
        if let projectBucket, displayTitle != projectBucket {
            return "\(projectBucket)  ·  \(compact)"
        }
        return compact
    }

    var searchText: String {
        var parts = [
            command,
            user,
            String(port),
            String(pid),
            displayTitle
        ]
        if let serviceName { parts.append(serviceName) }
        if let commandLine { parts.append(commandLine) }
        if let workingDirectory { parts.append(workingDirectory) }
        if let projectLabel { parts.append(projectLabel) }
        if let toolLabel { parts.append(toolLabel) }
        parts.append(contentsOf: endpoints)
        return parts.joined(separator: " ").lowercased()
    }

    private var identity: ProcessIdentity {
        ProcessIdentity(
            workingDirectory: workingDirectory,
            projectLabel: projectLabel,
            toolLabel: toolLabel,
            isProjectServer: isProjectServer
        )
    }
}

enum EntrySortMode: Int, CaseIterable, Identifiable {
    case newest
    case port

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .newest: return "Newest"
        case .port: return "Port"
        }
    }

    var segmentIndex: Int { rawValue }

    init?(segmentIndex: Int) {
        self.init(rawValue: segmentIndex)
    }
}

enum EntryScope: Int, CaseIterable, Identifiable {
    case project
    case all
    case other

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .project: return "Projects"
        case .all: return "All"
        case .other: return "Other"
        }
    }
}

enum PortScanOutcome {
    case success([PortEntry])
    case failure(String)
}
