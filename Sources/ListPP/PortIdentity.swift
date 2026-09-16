import Foundation

struct ProcessIdentity: Hashable {
    let workingDirectory: String?
    let projectLabel: String?
    let toolLabel: String?
    let isProjectServer: Bool

    var projectName: String? {
        guard let projectLabel else { return nil }
        return projectLabel.split(separator: "/").map(String.init).last
    }

    var projectBucket: String? {
        guard let projectLabel else { return nil }
        let parts = projectLabel.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        return parts[0]
    }

    func displayTitle(fallbackCommand: String) -> String {
        if let projectName { return projectName }
        if let folder = PortIdentity.usefulFolderName(from: workingDirectory) {
            return folder
        }
        if let toolLabel { return toolLabel }
        return fallbackCommand
    }
}

enum PortIdentity {
    static let projectRootFolder = "Project"

    static let localDevTools: Set<String> = [
        "Vite", "Next.js", "Nuxt", "Remix", "Astro", "SvelteKit",
        "Webpack", "Parcel", "esbuild", "Turbo", "Wrangler",
        "Nodemon", "Uvicorn", "Gunicorn", "Hypercorn",
        "FastAPI", "Flask", "Django", "http.server",
        "Streamlit", "Gradio", "Jupyter", "Celery",
        "Rails", "Puma", "Sidekiq", "PHP", "Artisan"
    ]

    private static let systemCommands: Set<String> = [
        "controlcenter", "rapportd", "sharingd", "identityservicesd",
        "figma", "figma helper", "aside", "codex",
        "spotify", "slack", "zoom.us", "discord",
        "google chrome", "chrome", "safari", "firefox",
        "coreaudiod", "bluetoothd", "airplayxpchelper",
        "usernoted", "notificationcenter"
    ]

    private static let systemPathPrefixes = [
        "/System", "/Library", "/usr", "/bin", "/sbin",
        "/private", "/opt/homebrew", "/opt/local", "/Applications"
    ]

    static func resolve(
        command: String,
        commandLine: String?,
        workingDirectory: String?,
        homeDirectory: String
    ) -> ProcessIdentity {
        let inferredProjectPath = firstProjectPath(in: commandLine, homeDirectory: homeDirectory)
        let cwd = normalizedPath(workingDirectory) ?? inferredProjectPath
        let projectLabel = firstProjectLabel(
            paths: [cwd, inferredProjectPath].compactMap { $0 },
            homeDirectory: homeDirectory
        )
        let toolLabel = inferTool(command: command, commandLine: commandLine)
        let isProject = isProjectServer(
            command: command,
            projectLabel: projectLabel,
            toolLabel: toolLabel,
            workingDirectory: cwd
        )

        return ProcessIdentity(
            workingDirectory: cwd,
            projectLabel: projectLabel,
            toolLabel: toolLabel,
            isProjectServer: isProject
        )
    }

    static func compactPath(_ path: String, homeDirectory: String) -> String {
        let standardized = normalizedPath(path) ?? path
        let home = normalizedPath(homeDirectory) ?? homeDirectory
        if standardized == home {
            return "~"
        }
        if standardized.hasPrefix(home + "/") {
            return "~" + standardized.dropFirst(home.count)
        }
        return standardized
    }

    static func usefulFolderName(from path: String?) -> String? {
        guard let path = normalizedPath(path) else { return nil }
        if isSystemPath(path) { return nil }
        let name = URL(fileURLWithPath: path).lastPathComponent
        if name.isEmpty || name == "/" { return nil }
        return name
    }

    static func parseLsofCwdFields(_ stdout: String) -> [Int: String] {
        var map: [Int: String] = [:]
        var currentPID: Int?

        for rawLine in stdout.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let marker = line.first else { continue }
            let value = String(line.dropFirst())
            switch marker {
            case "p":
                currentPID = Int(value)
            case "n":
                guard let pid = currentPID else { continue }
                if let path = normalizedPath(value), path != "/" {
                    map[pid] = path
                }
            default:
                continue
            }
        }

        return map
    }

    static func projectLabel(from path: String, homeDirectory: String) -> String? {
        guard let remainder = projectRelativePath(from: path, homeDirectory: homeDirectory) else {
            return nil
        }
        let parts = remainder.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        if parts.count >= 2 {
            return "\(parts[0])/\(parts[1])"
        }
        return parts[0]
    }

    private static func isProjectServer(
        command: String,
        projectLabel: String?,
        toolLabel: String?,
        workingDirectory: String?
    ) -> Bool {
        if projectLabel != nil {
            return true
        }
        if systemCommands.contains(command.lowercased()) {
            return false
        }
        if let workingDirectory, isSystemPath(workingDirectory) {
            return false
        }
        if let toolLabel, localDevTools.contains(toolLabel) {
            return true
        }
        return false
    }

    private static func firstProjectLabel(paths: [String], homeDirectory: String) -> String? {
        for path in paths {
            if let label = projectLabel(from: path, homeDirectory: homeDirectory) {
                return label
            }
        }
        return nil
    }

    private static func firstProjectPath(in commandLine: String?, homeDirectory: String) -> String? {
        guard let commandLine, !commandLine.isEmpty else { return nil }
        let home = normalizedPath(homeDirectory) ?? homeDirectory
        let marker = home + "/" + projectRootFolder + "/"

        var searchStart = commandLine.startIndex
        while let range = commandLine.range(of: marker, range: searchStart..<commandLine.endIndex) {
            let token = commandLine[range.lowerBound...]
                .prefix(while: { !$0.isWhitespace && $0 != "'" && $0 != "\"" && $0 != "`" })
            if let labelPath = projectRootPath(from: String(token), homeDirectory: home) {
                return labelPath
            }
            searchStart = range.upperBound
        }
        return nil
    }

    private static func projectRootPath(from path: String, homeDirectory: String) -> String? {
        guard let remainder = projectRelativePath(from: path, homeDirectory: homeDirectory) else {
            return nil
        }
        let parts = remainder.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        var root = (normalizedPath(homeDirectory) ?? homeDirectory) as NSString
        root = root.appendingPathComponent(projectRootFolder) as NSString
        let take = min(2, parts.count)
        for part in parts.prefix(take) {
            root = root.appendingPathComponent(part) as NSString
        }
        return root as String
    }

    private static func projectRelativePath(from path: String, homeDirectory: String) -> String? {
        guard let standardized = normalizedPath(path) else { return nil }
        let home = normalizedPath(homeDirectory) ?? homeDirectory
        let root = (home as NSString).appendingPathComponent(projectRootFolder)
        let standardizedRoot = normalizedPath(root) ?? root
        if standardized == standardizedRoot {
            return ""
        }
        guard standardized.hasPrefix(standardizedRoot + "/") else {
            return nil
        }
        return String(standardized.dropFirst(standardizedRoot.count + 1))
    }

    private static func inferTool(command: String, commandLine: String?) -> String? {
        let commandLower = command.lowercased()
        let line = (commandLine ?? "").lowercased()
        let tokens = tokenize(command: command, commandLine: commandLine)

        func has(_ names: String...) -> Bool {
            names.contains { tokens.contains($0) }
        }

        func mentions(_ fragments: String...) -> Bool {
            fragments.contains { line.contains($0) || commandLower.contains($0) }
        }

        if has("next-server")
            || commandLower == "next"
            || mentions("node_modules/next/", "next/dist/", "next-server") {
            return "Next.js"
        }
        if has("vite") || mentions("node_modules/vite/") {
            return "Vite"
        }
        if has("nuxt") || mentions("node_modules/nuxt/") {
            return "Nuxt"
        }
        if has("remix") || mentions("node_modules/@remix-run/", "node_modules/remix/") {
            return "Remix"
        }
        if has("astro") || mentions("node_modules/astro/") {
            return "Astro"
        }
        if has("svelte-kit", "sveltekit") || mentions("node_modules/@sveltejs/kit/") {
            return "SvelteKit"
        }
        if has("webpack", "webpack-dev-server") || mentions("node_modules/webpack/") {
            return "Webpack"
        }
        if has("parcel") || mentions("node_modules/parcel/") {
            return "Parcel"
        }
        if has("esbuild") || mentions("node_modules/esbuild/") {
            return "esbuild"
        }
        if has("turbo") || mentions("node_modules/turbo/") {
            return "Turbo"
        }
        if has("wrangler") || mentions("node_modules/wrangler/") {
            return "Wrangler"
        }
        if has("nodemon") || mentions("node_modules/nodemon/") {
            return "Nodemon"
        }
        if has("uvicorn") || mentions("-m uvicorn") {
            return "Uvicorn"
        }
        if has("gunicorn") || mentions("-m gunicorn") {
            return "Gunicorn"
        }
        if has("hypercorn") || mentions("-m hypercorn") {
            return "Hypercorn"
        }
        if has("fastapi") || mentions("-m fastapi") {
            return "FastAPI"
        }
        if has("flask") || mentions("-m flask") {
            return "Flask"
        }
        if has("django", "manage.py") || mentions("manage.py", "django.core") {
            return "Django"
        }
        if mentions("http.server") {
            return "http.server"
        }
        if has("streamlit") || mentions("-m streamlit") {
            return "Streamlit"
        }
        if has("gradio") || mentions("-m gradio") {
            return "Gradio"
        }
        if has("jupyter", "notebook") || mentions("-m jupyter", "-m notebook") {
            return "Jupyter"
        }
        if has("celery") {
            return "Celery"
        }
        if has("puma") {
            return "Puma"
        }
        if has("rails", "rackup") {
            return "Rails"
        }
        if has("sidekiq") {
            return "Sidekiq"
        }
        if has("artisan") || mentions("artisan serve") {
            return "Artisan"
        }
        if commandLower == "php" || has("php") {
            return "PHP"
        }
        if has("postgres", "postmaster") {
            return "PostgreSQL"
        }
        if has("mysqld", "mysql") {
            return "MySQL"
        }
        if has("redis-server") {
            return "Redis"
        }
        if has("mongod") {
            return "MongoDB"
        }
        if has("nginx") {
            return "nginx"
        }
        if has("httpd", "apache2") {
            return "Apache"
        }
        if commandLower == "python" || commandLower == "python3" || commandLower.hasPrefix("python") {
            return "Python"
        }
        if commandLower == "node" || commandLower == "nodejs" {
            return "Node"
        }
        if commandLower == "ruby" {
            return "Ruby"
        }
        if commandLower == "java" {
            return "Java"
        }
        return nil
    }

    private static func tokenize(command: String, commandLine: String?) -> Set<String> {
        var tokens: Set<String> = [command.lowercased()]
        guard let commandLine else { return tokens }

        for raw in commandLine.split(whereSeparator: \.isWhitespace) {
            let trimmed = String(raw).trimmingCharacters(in: CharacterSet(charactersIn: "'\"`"))
            guard !trimmed.isEmpty else { continue }
            tokens.insert(trimmed.lowercased())
            tokens.insert(URL(fileURLWithPath: trimmed).lastPathComponent.lowercased())
            for part in trimmed.split(separator: "/") {
                let value = String(part).lowercased()
                if !value.isEmpty {
                    tokens.insert(value)
                }
            }
        }

        return tokens
    }

    private static func isSystemPath(_ path: String) -> Bool {
        systemPathPrefixes.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    private static func normalizedPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed).standardizedFileURL.path
    }
}
