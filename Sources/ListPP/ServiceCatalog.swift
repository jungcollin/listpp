import Foundation

final class ServiceCatalog {
    private let commandHints: [String: String] = [
        "postgres": "postgresql",
        "postmaster": "postgresql",
        "mysqld": "mysql",
        "redis-server": "redis",
        "mongod": "mongodb",
        "nginx": "http",
        "httpd": "http",
        "apache2": "http",
        "sshd": "ssh",
        "docker-proxy": "docker"
    ]
    private let tcpPortMap: [Int: String]

    init(servicesFilePath: String = "/etc/services") {
        self.tcpPortMap = ServiceCatalog.loadTCPServices(from: servicesFilePath)
    }

    func resolveServiceName(port: Int, command: String) -> String? {
        let normalized = command.lowercased()
        if let hinted = commandHints[normalized] {
            return hinted
        }
        return tcpPortMap[port]
    }

    private static func loadTCPServices(from path: String) -> [Int: String] {
        guard let file = try? String(contentsOfFile: path, encoding: .utf8) else {
            return [:]
        }

        var map: [Int: String] = [:]

        for rawLine in file.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            let withoutComment = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            let tokens = withoutComment.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard tokens.count >= 2 else {
                continue
            }

            let service = String(tokens[0])
            let portProto = tokens[1].split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            guard portProto.count == 2 else {
                continue
            }
            guard portProto[1].lowercased() == "tcp" else {
                continue
            }
            guard let port = Int(portProto[0]) else {
                continue
            }

            if map[port] == nil {
                map[port] = service
            }
        }

        return map
    }
}
