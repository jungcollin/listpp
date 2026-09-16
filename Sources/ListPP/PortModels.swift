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

    var canRestart: Bool {
        guard let commandLine else { return false }
        return !commandLine.isEmpty
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

enum PortScanOutcome {
    case success([PortEntry])
    case failure(String)
}
