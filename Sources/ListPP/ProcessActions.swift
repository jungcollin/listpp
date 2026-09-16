import AppKit
import Foundation

enum ProcessActionError: LocalizedError {
    case commandFailed(String)
    case missingCommandLine

    var errorDescription: String? {
        switch self {
        case .commandFailed(let detail):
            return detail.isEmpty ? "No additional details are available." : detail
        case .missingCommandLine:
            return "Command line is unavailable for relaunch."
        }
    }
}

enum ProcessActions {
    static func terminate(pid: Int) throws {
        guard let killResult = Shell.run("/bin/kill", ["-TERM", String(pid)]) else {
            throw ProcessActionError.commandFailed("Failed to execute kill command.")
        }

        guard killResult.status == 0 else {
            let detail = killResult.stderr.isEmpty ? killResult.stdout : killResult.stderr
            throw ProcessActionError.commandFailed(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func relaunch(commandLine: String, workingDirectory: String? = nil) throws {
        let relaunched = Shell.launchDetached(
            "/bin/zsh",
            ["-lc", commandLine],
            currentDirectory: workingDirectory
        )
        guard relaunched else {
            throw ProcessActionError.commandFailed("Failed to relaunch command.")
        }
    }
}

enum AppAlerts {
    @discardableResult
    static func confirmRestart(entry: PortEntry) -> Bool {
        let confirmation = NSAlert()
        confirmation.alertStyle = .warning
        confirmation.messageText = "Restart \(entry.displayTitle)?"
        var details = [
            "Sends SIGTERM to \(entry.command) (\(entry.pid)) on port \(entry.port) and relaunches the same command line."
        ]
        if let workingDirectory = entry.workingDirectory {
            let compact = PortIdentity.compactPath(
                workingDirectory,
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path
            )
            details.append("cwd: \(compact)")
        }
        details.append("Cmd: \(TextPreview.truncate(entry.commandLine ?? "", maxLength: 180))")
        confirmation.informativeText = details.joined(separator: "\n")
        confirmation.addButton(withTitle: "Restart")
        confirmation.addButton(withTitle: "Cancel")
        return confirmation.runModal() == .alertFirstButtonReturn
    }

    static func showError(title: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail.isEmpty ? "No additional details are available." : detail
        alert.runModal()
    }
}

enum TextPreview {
    static func truncate(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let end = text.index(text.startIndex, offsetBy: maxLength)
        return String(text[..<end]) + "..."
    }

    static func tailPreview(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let start = text.index(text.endIndex, offsetBy: -maxLength)
        return "..." + String(text[start...])
    }
}

enum TimeDisplay {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    static func updatedText(from date: Date?) -> String {
        guard let date else { return "Not updated yet" }
        return "Updated \(formatter.string(from: date))"
    }

    static func timeText(from date: Date?) -> String {
        guard let date else { return "—" }
        return formatter.string(from: date)
    }
}
