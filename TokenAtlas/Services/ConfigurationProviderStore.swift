import Foundation

enum ConfigurationProviderStoreError: LocalizedError, Sendable {
    case unsupportedCLI
    case invalidClaudeJSON
    case invalidCodexConfig
    case providerNotFound
    case codexLoginRequired(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedCLI:
            "Only Claude Code and Codex are supported in this switcher."
        case .invalidClaudeJSON:
            "Claude provider raw config must be a JSON object."
        case .invalidCodexConfig:
            "Codex provider raw config must be valid provider TOML text."
        case .providerNotFound:
            "The selected API provider could not be found."
        case .codexLoginRequired(let message):
            message
        }
    }
}

struct ConfigurationProviderApplyResult: Sendable, Hashable {
    let backupDirectory: URL
    let appliedAt: Date
}

struct ConfigurationProviderStore: Sendable {
    static let codexManagedProviderKey = "TokenAtlas"

    let rootDirectory: URL
    let claudePaths: ClaudePaths
    let codexPaths: CodexPaths
    let secretStore: any APIProviderSecretStoring

    private var libraryURL: URL {
        rootDirectory.appendingPathComponent("providers.json", isDirectory: false)
    }

    private var backupsDirectory: URL {
        rootDirectory.appendingPathComponent("Backups", isDirectory: true)
    }

    private var claudeSettingsURL: URL {
        claudePaths.configDirectory.appendingPathComponent("settings.json", isDirectory: false)
    }

    private var codexAuthURL: URL {
        codexPaths.homeDirectory.appendingPathComponent("auth.json", isDirectory: false)
    }

    private var codexConfigURL: URL {
        codexPaths.homeDirectory.appendingPathComponent("config.toml", isDirectory: false)
    }

    init(
        rootDirectory: URL = Self.defaultRootDirectory(),
        claudePaths: ClaudePaths = .default,
        codexPaths: CodexPaths = .default,
        secretStore: any APIProviderSecretStoring = APIProviderKeychainStore.shared
    ) {
        self.rootDirectory = rootDirectory
        self.claudePaths = claudePaths
        self.codexPaths = codexPaths
        self.secretStore = secretStore
    }

    static func defaultRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("TokenAtlas", isDirectory: true)
            .appendingPathComponent("APIProviders", isDirectory: true)
    }

    func loadLibrary() async throws -> ConfigurationProviderLibrary {
        let url = libraryURL
        return try await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return ConfigurationProviderLibrary()
            }
            let data = try Data(contentsOf: url)
            return try JSONDecoder.apiProviderDecoder.decode(ConfigurationProviderLibrary.self, from: data)
        }.value
    }

    func saveLibrary(_ library: ConfigurationProviderLibrary) async throws {
        let rootDirectory = rootDirectory
        let url = libraryURL
        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder.apiProviderEncoder.encode(library)
            try data.write(to: url, options: .atomic)
        }.value
    }

    func deleteStoredSecrets(_ secrets: [APIProviderSecret], retainedIn library: ConfigurationProviderLibrary) {
        let retainedAccounts = Self.keychainAccounts(in: library)
        let accounts = Set(secrets.compactMap(\.keychainAccount))
        for account in accounts where !retainedAccounts.contains(account) {
            secretStore.deleteAPIKey(account: account)
        }
    }

    func ensureSystemProviders(
        in library: ConfigurationProviderLibrary,
        keyStorageMode _: APIProviderKeyStorageMode
    ) async throws -> ConfigurationProviderLibrary {
        var updated = library
        for cli in APIProviderCLI.allCases {
            if !updated.cliProviders.contains(where: { $0.cli == cli && $0.id == "official" }) {
                updated.cliProviders.append(Self.officialProvider(for: cli))
            }
        }
        return updated
    }

    func importCurrentProvider(
        cli: APIProviderCLI,
        name: String,
        id: String = UUID().uuidString,
        keyStorageMode: APIProviderKeyStorageMode
    ) async throws -> CLIAPIProvider {
        switch cli {
        case .claude:
            let live = try await readClaudeSettingsText()
            return try providerFromClaudeRaw(
                id: id,
                name: name,
                origin: .importedDefault,
                category: .imported,
                rawConfig: live,
                keyStorageMode: keyStorageMode,
                createdAt: .now
            )
        case .codex:
            let live = try await readCodexLive()
            return try providerFromCodexRaw(
                id: id,
                name: name,
                origin: .importedDefault,
                category: .imported,
                rawConfig: live.config,
                authJSON: live.auth,
                keyStorageMode: keyStorageMode,
                createdAt: .now
            )
        }
    }

    func claudeSettingsCandidates() async -> [ClaudeSettingsCandidate] {
        let directory = claudePaths.configDirectory
        return await Task.detached(priority: .utility) {
            Self.claudeSettingsCandidates(in: directory)
        }.value
    }

    func importClaudeSettingsCandidate(
        _ candidate: ClaudeSettingsCandidate,
        keyStorageMode: APIProviderKeyStorageMode
    ) async throws -> CLIAPIProvider {
        let raw = try await Task.detached(priority: .utility) {
            try String(contentsOf: candidate.url, encoding: .utf8)
        }.value
        return try providerFromClaudeRaw(
            id: Self.providerID(forClaudeSettingsCandidate: candidate),
            name: candidate.title,
            origin: .appSpecific,
            category: .imported,
            rawConfig: raw,
            keyStorageMode: keyStorageMode,
            createdAt: .now
        )
    }

    func providerBySavingDraft(
        existing: CLIAPIProvider,
        name: String,
        category: APIProviderCategory,
        baseURL: String,
        apiKey: String,
        model: String,
        rawConfig: String,
        rawMode: Bool,
        keyStorageMode: APIProviderKeyStorageMode
    ) throws -> CLIAPIProvider {
        let savedAt = Date()
        if rawMode {
            switch existing.cli {
            case .claude:
                var provider = try providerFromClaudeRaw(
                    id: existing.id,
                    name: name,
                    origin: existing.origin,
                    category: category,
                    rawConfig: rawConfig,
                    keyStorageMode: keyStorageMode,
                    createdAt: existing.createdAt,
                    updatedAt: savedAt
                )
                provider.iconName = existing.iconName
                provider.iconColorHex = existing.iconColorHex
                return provider
            case .codex:
                var provider = try providerFromCodexRaw(
                    id: existing.id,
                    name: name,
                    origin: existing.origin,
                    category: category,
                    rawConfig: rawConfig,
                    authJSON: ["OPENAI_API_KEY": apiKey],
                    keyStorageMode: keyStorageMode,
                    createdAt: existing.createdAt,
                    updatedAt: savedAt
                )
                provider.iconName = existing.iconName
                provider.iconColorHex = existing.iconColorHex
                return provider
            }
        }

        var provider = existing
        provider.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? existing.name : name.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.category = category
        provider.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.apiKey = try storedSecret(rawKey: apiKey, cli: existing.cli, providerID: existing.id, keyStorageMode: keyStorageMode)
        provider.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.rawConfig = storedRawConfig(for: provider, keyStorageMode: keyStorageMode)
        provider.updatedAt = savedAt
        return provider
    }

    func makeCustomProvider(cli: APIProviderCLI, keyStorageMode: APIProviderKeyStorageMode) -> CLIAPIProvider {
        let id = UUID().uuidString
        var provider = CLIAPIProvider(
            id: id,
            cli: cli,
            origin: .appSpecific,
            name: "New Provider",
            category: .custom,
            baseURL: "",
            apiKey: .none,
            model: defaultModel(for: cli),
            iconName: cli.providerKind.monochromeAssetName
        )
        provider.rawConfig = storedRawConfig(for: provider, keyStorageMode: keyStorageMode)
        return provider
    }

    func makeUniversalProvider(keyStorageMode: APIProviderKeyStorageMode) -> (UniversalAPIProvider, [CLIAPIProvider]) {
        let universal = UniversalAPIProvider(
            name: "Universal Provider",
            baseURL: "",
            apiKey: .none,
            modelOverrides: [.claude: defaultModel(for: .claude), .codex: defaultModel(for: .codex)],
            iconName: "network"
        )
        return (universal, childProviders(for: universal, keyStorageMode: keyStorageMode))
    }

    func universalBySavingDraft(
        existing: UniversalAPIProvider,
        editedCLI: APIProviderCLI,
        name: String,
        baseURL: String,
        apiKey: String,
        model: String,
        keyStorageMode: APIProviderKeyStorageMode
    ) throws -> UniversalAPIProvider {
        var provider = existing
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.name = trimmedName.isEmpty ? existing.name : trimmedName
        provider.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.apiKey = try storedSecret(
            rawKey: apiKey,
            cli: editedCLI,
            providerID: existing.id,
            keyStorageMode: keyStorageMode
        )
        provider.modelOverrides[editedCLI] = model.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.updatedAt = .now
        return provider
    }

    func childProviders(for universal: UniversalAPIProvider, keyStorageMode: APIProviderKeyStorageMode) -> [CLIAPIProvider] {
        APIProviderCLI.allCases.compactMap { cli in
            guard universal.enabledCLIs.contains(cli) else { return nil }
            let id = Self.universalChildID(universalID: universal.id, cli: cli)
            var provider = CLIAPIProvider(
                id: id,
                cli: cli,
                origin: .universal(universal.id),
                name: universal.name,
                category: .universal,
                baseURL: universal.baseURL,
                apiKey: universal.apiKey,
                model: universal.modelOverrides[cli] ?? defaultModel(for: cli),
                iconName: universal.iconName,
                iconColorHex: universal.iconColorHex,
                createdAt: universal.createdAt,
                updatedAt: universal.updatedAt
            )
            provider.rawConfig = storedRawConfig(for: provider, keyStorageMode: keyStorageMode)
            return provider
        }
    }

    func apply(
        provider: CLIAPIProvider,
        currentActive: CLIAPIProvider?,
        keyStorageMode: APIProviderKeyStorageMode
    ) async throws -> (ConfigurationProviderApplyResult, CLIAPIProvider?) {
        let backfilled: CLIAPIProvider?
        if let currentActive, currentActive.id != provider.id {
            backfilled = try await backfilledProvider(currentActive, keyStorageMode: keyStorageMode)
        } else {
            backfilled = nil
        }

        let backupDirectory = try await backupLiveFiles(for: provider.cli, providerID: provider.id)
        try await writeLiveConfig(for: provider)
        return (
            ConfigurationProviderApplyResult(backupDirectory: backupDirectory, appliedAt: .now),
            backfilled
        )
    }

    func resolvedAPIKey(for secret: APIProviderSecret) -> String {
        switch secret {
        case .none:
            return ""
        case .inline(let value):
            return value
        case .keychain(let account):
            return secretStore.readAPIKey(account: account) ?? ""
        }
    }

    func renderRawConfig(for provider: CLIAPIProvider) -> String {
        switch provider.cli {
        case .claude:
            return renderClaudeRaw(provider: provider, apiKey: resolvedAPIKey(for: provider.apiKey))
        case .codex:
            return renderCodexConfig(provider: provider)
        }
    }

    func renderRawConfig(for provider: CLIAPIProvider, resolvedAPIKey apiKey: String) -> String {
        switch provider.cli {
        case .claude:
            return renderClaudeRaw(provider: provider, apiKey: apiKey)
        case .codex:
            return renderCodexConfig(provider: provider)
        }
    }

    func codexChannelStatus(activeProvider: CLIAPIProvider?) async -> CodexChannelStatus {
        let configURL = codexConfigURL
        let authURL = codexAuthURL
        let task = Task.detached(priority: .utility) {
            let config = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
            let auth = Self.codexAuthStatus(authURL: authURL)
            let activeProviderKey = Self.rootTomlValue(named: "model_provider", in: config)
            let providerValues = Self.tomlTableValues(named: "model_providers.\(Self.codexManagedProviderKey)", in: config)
            let channel: CodexModelChannel = activeProviderKey == Self.codexManagedProviderKey ? .hybridRelay : .official
            let baseURL = providerValues?["base_url"].map(Self.unquoteTomlString)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let token = providerValues?["experimental_bearer_token"].map(Self.unquoteTomlString)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let requiresOpenAIAuth = providerValues?["requires_openai_auth"]?.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
            return CodexChannelStatus(
                channel: channel,
                configPath: configURL.path,
                authPath: authURL.path,
                configured: channel == .hybridRelay && !baseURL.isEmpty && !token.isEmpty && requiresOpenAIAuth,
                authenticated: auth.authenticated,
                accountLabel: auth.accountLabel,
                activeProfileName: channel == .hybridRelay
                    ? Self.codexActiveProfileName(activeProvider: activeProvider)
                    : "官方通道"
            )
        }
        return await task.value
    }

    private static func codexActiveProfileName(activeProvider: CLIAPIProvider?) -> String {
        guard let activeProvider,
              activeProvider.origin.kind != .official,
              !activeProvider.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return codexManagedProviderKey
        }
        return activeProvider.name
    }

    static func officialProvider(for cli: APIProviderCLI) -> CLIAPIProvider {
        var provider = CLIAPIProvider(
            id: "official",
            cli: cli,
            origin: .official,
            name: cli == .claude ? "Claude Official" : "OpenAI Official",
            category: .official,
            baseURL: "",
            apiKey: .none,
            model: "",
            iconName: cli == .claude ? "anthropic" : "openai",
            iconColorHex: cli == .claude ? "#D4915D" : "#00A67E"
        )
        provider.rawConfig = cli == .claude ? "{\n  \"env\" : {\n\n  }\n}" : ""
        return provider
    }

    static func universalChildID(universalID: String, cli: APIProviderCLI) -> String {
        "universal-\(cli.rawValue)-\(universalID)"
    }

    static func claudeSettingsVariantSources(in directory: URL) -> [AIConfigSource] {
        claudeSettingsVariantURLs(in: directory).map { url in
            AIConfigSource(
                provider: .claude,
                title: url.lastPathComponent,
                url: url,
                kind: .providerConfig,
                fileKind: .json,
                location: .global
            )
        }
    }

    private static func claudeSettingsCandidates(in directory: URL) -> [ClaudeSettingsCandidate] {
        claudeSettingsVariantURLs(in: directory).compactMap { url in
            guard let raw = try? String(contentsOf: url, encoding: .utf8),
                  let data = raw.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            let env = object["env"] as? [String: Any] ?? [:]
            let baseURL = env["ANTHROPIC_BASE_URL"] as? String ?? ""
            let model = (env["ANTHROPIC_MODEL"] as? String)
                ?? (env["ANTHROPIC_DEFAULT_OPUS_MODEL"] as? String)
                ?? (env["ANTHROPIC_DEFAULT_SONNET_MODEL"] as? String)
                ?? (env["ANTHROPIC_DEFAULT_HAIKU_MODEL"] as? String)
                ?? ""
            let label = claudeSettingsVariantLabel(from: url)
            return ClaudeSettingsCandidate(
                title: displayName(forClaudeSettingsLabel: label),
                label: label,
                url: url,
                baseURL: baseURL,
                model: model
            )
        }
    }

    private static func claudeSettingsVariantURLs(in directory: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents
            .filter { url in
                guard url.pathExtension == "json",
                      url.lastPathComponent.hasPrefix("settings."),
                      url.lastPathComponent.hasSuffix(".json"),
                      url.lastPathComponent != "settings.json",
                      url.lastPathComponent != "settings.local.json" else {
                    return false
                }
                return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func providerID(forClaudeSettingsCandidate candidate: ClaudeSettingsCandidate) -> String {
        "claude-settings-\(candidate.label)"
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "-"
            }
            .reduce(into: "") { partial, character in
                if character == "-", partial.last == "-" { return }
                partial.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func claudeSettingsVariantLabel(from url: URL) -> String {
        let fileName = url.lastPathComponent
        let withoutPrefix = fileName.dropFirst("settings.".count)
        return String(withoutPrefix.dropLast(".json".count))
    }

    private static func displayName(forClaudeSettingsLabel label: String) -> String {
        label
            .split { !$0.isLetter && !$0.isNumber }
            .map { part in
                let text = String(part)
                return text.prefix(1).uppercased() + text.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func keychainAccounts(in library: ConfigurationProviderLibrary) -> Set<String> {
        var accounts = Set<String>()
        for provider in library.cliProviders {
            if let account = provider.apiKey.keychainAccount {
                accounts.insert(account)
            }
        }
        for provider in library.universalProviders {
            if let account = provider.apiKey.keychainAccount {
                accounts.insert(account)
            }
        }
        return accounts
    }

    private func readClaudeSettingsText() async throws -> String {
        let url = claudeSettingsURL
        return try await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return "{\n  \"env\" : {\n\n  }\n}"
            }
            return try String(contentsOf: url, encoding: .utf8)
        }.value
    }

    private func readCodexLive() async throws -> (auth: [String: String], config: String) {
        let authURL = codexAuthURL
        let configURL = codexConfigURL
        return try await Task.detached(priority: .utility) {
            let auth: [String: String]
            if FileManager.default.fileExists(atPath: authURL.path),
               let data = try? Data(contentsOf: authURL),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                auth = object.compactMapValues { $0 as? String }
            } else {
                auth = [:]
            }

            let config = FileManager.default.fileExists(atPath: configURL.path)
                ? (try String(contentsOf: configURL, encoding: .utf8))
                : ""
            return (auth, config)
        }.value
    }

    private func writeLiveConfig(for provider: CLIAPIProvider) async throws {
        switch provider.cli {
        case .claude:
            let target = renderClaudeRaw(provider: provider, apiKey: resolvedAPIKey(for: provider.apiKey))
            let url = claudeSettingsURL
            try await Task.detached(priority: .utility) {
                try Self.writeClaudeSettings(providerFragment: target, to: url)
            }.value
        case .codex:
            let config = renderCodexConfig(provider: provider)
            let key = resolvedAPIKey(for: provider.apiKey)
            let authURL = codexAuthURL
            let configURL = codexConfigURL
            try await Task.detached(priority: .utility) {
                try Self.writeCodexLive(configFragment: config, apiKey: key, authURL: authURL, configURL: configURL)
            }.value
        }
    }

    private func backupLiveFiles(for cli: APIProviderCLI, providerID: String) async throws -> URL {
        let backupsDirectory = backupsDirectory
        let sources: [URL]
        switch cli {
        case .claude:
            sources = [claudeSettingsURL]
        case .codex:
            sources = [codexAuthURL, codexConfigURL]
        }
        return try await Task.detached(priority: .utility) {
            let date = Date()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
            let stamp = formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
            let directory = backupsDirectory.appendingPathComponent("\(stamp)-\(cli.rawValue)-\(providerID)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            var entries: [[String: Any]] = []
            for (index, source) in sources.enumerated() {
                let exists = FileManager.default.fileExists(atPath: source.path)
                if exists {
                    let backup = directory.appendingPathComponent("\(index)-\(source.lastPathComponent)", isDirectory: false)
                    try FileManager.default.copyItem(at: source, to: backup)
                    entries.append(["targetPath": source.path, "backupPath": backup.path, "existed": true])
                } else {
                    entries.append(["targetPath": source.path, "existed": false])
                }
            }

            let manifest: [String: Any] = [
                "providerID": providerID,
                "cli": cli.rawValue,
                "createdAt": ISO8601DateFormatter().string(from: date),
                "files": entries,
            ]
            let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("manifest.json", isDirectory: false), options: .atomic)
            return directory
        }.value
    }

    private func backfilledProvider(_ provider: CLIAPIProvider, keyStorageMode: APIProviderKeyStorageMode) async throws -> CLIAPIProvider {
        switch provider.cli {
        case .claude:
            let raw = try await readClaudeSettingsText()
            var updated = try providerFromClaudeRaw(
                id: provider.id,
                name: provider.name,
                origin: provider.origin,
                category: provider.category,
                rawConfig: raw,
                keyStorageMode: keyStorageMode,
                createdAt: provider.createdAt
            )
            updated.iconName = provider.iconName
            updated.iconColorHex = provider.iconColorHex
            updated.updatedAt = .now
            return updated
        case .codex:
            let live = try await readCodexLive()
            var updated = try providerFromCodexRaw(
                id: provider.id,
                name: provider.name,
                origin: provider.origin,
                category: provider.category,
                rawConfig: live.config,
                authJSON: live.auth,
                keyStorageMode: keyStorageMode,
                createdAt: provider.createdAt
            )
            updated.iconName = provider.iconName
            updated.iconColorHex = provider.iconColorHex
            updated.updatedAt = .now
            return updated
        }
    }

    private func providerFromClaudeRaw(
        id: String,
        name: String,
        origin: APIProviderOrigin,
        category: APIProviderCategory,
        rawConfig: String,
        keyStorageMode: APIProviderKeyStorageMode,
        createdAt: Date,
        updatedAt: Date = .now
    ) throws -> CLIAPIProvider {
        guard let data = rawConfig.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigurationProviderStoreError.invalidClaudeJSON
        }
        let env = object["env"] as? [String: Any] ?? [:]
        let apiKey = (env["ANTHROPIC_AUTH_TOKEN"] as? String) ?? (env["ANTHROPIC_API_KEY"] as? String) ?? ""
        let baseURL = env["ANTHROPIC_BASE_URL"] as? String ?? ""
        let model = env["ANTHROPIC_MODEL"] as? String ?? ""
        var provider = CLIAPIProvider(
            id: id,
            cli: .claude,
            origin: origin,
            name: name,
            category: category,
            baseURL: baseURL,
            apiKey: try storedSecret(rawKey: apiKey, cli: .claude, providerID: id, keyStorageMode: keyStorageMode),
            model: model,
            rawConfig: rawConfig,
            iconName: "anthropic",
            iconColorHex: "#D4915D",
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        provider.rawConfig = storedRawConfig(for: provider, keyStorageMode: keyStorageMode)
        return provider
    }

    private func providerFromCodexRaw(
        id: String,
        name: String,
        origin: APIProviderOrigin,
        category: APIProviderCategory,
        rawConfig: String,
        authJSON: [String: String],
        keyStorageMode: APIProviderKeyStorageMode,
        createdAt: Date,
        updatedAt: Date = .now
    ) throws -> CLIAPIProvider {
        let parsed = Self.parseCodexProviderFields(rawConfig)
        let apiKey = parsed.apiKey.isEmpty ? (authJSON["OPENAI_API_KEY"] ?? "") : parsed.apiKey
        var provider = CLIAPIProvider(
            id: id,
            cli: .codex,
            origin: origin,
            name: name,
            category: category,
            baseURL: parsed.baseURL,
            apiKey: try storedSecret(rawKey: apiKey, cli: .codex, providerID: id, keyStorageMode: keyStorageMode),
            model: parsed.model,
            rawConfig: rawConfig,
            iconName: "openai",
            iconColorHex: "#00A67E",
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        provider.rawConfig = storedRawConfig(for: provider, keyStorageMode: keyStorageMode)
        return provider
    }

    private func storedSecret(
        rawKey: String,
        cli: APIProviderCLI,
        providerID: String,
        keyStorageMode: APIProviderKeyStorageMode
    ) throws -> APIProviderSecret {
        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }
        switch keyStorageMode {
        case .json:
            return .inline(trimmed)
        case .keychain:
            let account = "\(cli.rawValue)-\(providerID)"
            try secretStore.saveAPIKey(trimmed, account: account)
            return .keychain(account: account)
        }
    }

    private func storedRawConfig(for provider: CLIAPIProvider, keyStorageMode: APIProviderKeyStorageMode) -> String {
        switch provider.cli {
        case .claude:
            let key = keyStorageMode == .json ? resolvedAPIKey(for: provider.apiKey) : ""
            return renderClaudeRaw(provider: provider, apiKey: key)
        case .codex:
            return renderCodexConfig(provider: provider)
        }
    }

    private func renderClaudeRaw(provider: CLIAPIProvider, apiKey: String) -> String {
        var env: [String: String] = [:]
        if !provider.baseURL.isEmpty { env["ANTHROPIC_BASE_URL"] = provider.baseURL }
        if !apiKey.isEmpty { env["ANTHROPIC_AUTH_TOKEN"] = apiKey }
        if !provider.model.isEmpty {
            env["ANTHROPIC_MODEL"] = provider.model
            env["ANTHROPIC_DEFAULT_HAIKU_MODEL"] = provider.model
            env["ANTHROPIC_DEFAULT_SONNET_MODEL"] = provider.model
            env["ANTHROPIC_DEFAULT_OPUS_MODEL"] = provider.model
        }
        let object: [String: Any] = ["env": env]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let raw = String(data: data, encoding: .utf8) else {
            return "{\n  \"env\" : {\n\n  }\n}"
        }
        return raw
    }

    private func renderCodexConfig(provider: CLIAPIProvider) -> String {
        guard !provider.baseURL.isEmpty else { return "" }
        let key = Self.codexManagedProviderKey
        let bearerToken = resolvedAPIKey(for: provider.apiKey)
        var lines = [
            "model_provider = \"\(key)\"",
            "",
            "[model_providers.\(key)]",
            "name = \"\(Self.tomlEscape(key))\"",
            "wire_api = \"responses\"",
            "requires_openai_auth = true",
            "base_url = \"\(Self.tomlEscape(provider.baseURL))\"",
        ]
        if !bearerToken.isEmpty {
            lines.append("experimental_bearer_token = \"\(Self.tomlEscape(bearerToken))\"")
        }
        return lines.joined(separator: "\n")
    }

    private func defaultModel(for cli: APIProviderCLI) -> String {
        switch cli {
        case .claude: ""
        case .codex: "gpt-5.4"
        }
    }

    private static func writeClaudeSettings(providerFragment: String, to url: URL) throws {
        let target = try jsonObject(from: providerFragment)
        let targetEnv = target["env"] as? [String: Any] ?? [:]
        let existing: [String: Any]
        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            existing = object
        } else {
            existing = [:]
        }

        var merged = existing
        var env = merged["env"] as? [String: Any] ?? [:]
        for key in claudeManagedEnvKeys {
            env.removeValue(forKey: key)
        }
        for (key, value) in targetEnv {
            if let string = value as? String, string.isEmpty { continue }
            env[key] = value
        }
        if env.isEmpty {
            merged.removeValue(forKey: "env")
        } else {
            merged["env"] = env
        }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private static func writeCodexLive(configFragment: String, apiKey _: String, authURL: URL, configURL: URL) throws {
        let auth = codexAuthStatus(authURL: authURL)
        let current = FileManager.default.fileExists(atPath: configURL.path)
            ? (try String(contentsOf: configURL, encoding: .utf8))
            : ""
        let common = stripCodexManagedConfig(from: current)
        let fragment = configFragment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fragment.isEmpty && !auth.authenticated {
            throw ConfigurationProviderStoreError.codexLoginRequired(auth.message)
        }
        let next = [fragment, common]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try next.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private static func jsonObject(from raw: String) throws -> [String: Any] {
        guard let data = raw.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigurationProviderStoreError.invalidClaudeJSON
        }
        return object
    }

    private static let claudeManagedEnvKeys: Set<String> = [
        "ANTHROPIC_BASE_URL",
        "ANTHROPIC_AUTH_TOKEN",
        "ANTHROPIC_API_KEY",
        "ANTHROPIC_MODEL",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL",
        "ANTHROPIC_DEFAULT_SONNET_MODEL",
        "ANTHROPIC_DEFAULT_OPUS_MODEL",
        "API_TIMEOUT_MS",
    ]

    private static func parseCodexProviderFields(_ raw: String) -> (baseURL: String, model: String, apiKey: String) {
        let model = firstTomlValue(named: "model", in: raw) ?? ""
        let activeProvider = rootTomlValue(named: "model_provider", in: raw)
        let activeValues = activeProvider.flatMap { Self.tomlTableValues(named: "model_providers.\($0)", in: raw) }
        let tokenAtlasValues = Self.tomlTableValues(named: "model_providers.\(Self.codexManagedProviderKey)", in: raw)
        let baseURL = activeValues?["base_url"].map(Self.unquoteTomlString)
            ?? tokenAtlasValues?["base_url"].map(Self.unquoteTomlString)
            ?? firstTomlValue(named: "base_url", in: raw)
            ?? ""
        let apiKey = activeValues?["experimental_bearer_token"].map(Self.unquoteTomlString)
            ?? tokenAtlasValues?["experimental_bearer_token"].map(Self.unquoteTomlString)
            ?? rootTomlValue(named: "OPENAI_API_KEY", in: raw)
            ?? ""
        return (baseURL, model, apiKey)
    }

    private static func firstTomlValue(named key: String, in raw: String) -> String? {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = #"(?m)^\s*\#(escapedKey)\s*=\s*"([^"]*)"\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRaw = raw as NSString
        let range = NSRange(location: 0, length: nsRaw.length)
        guard let match = regex.firstMatch(in: raw, range: range), match.numberOfRanges >= 2 else {
            return nil
        }
        return nsRaw.substring(with: match.range(at: 1))
    }

    private static func tomlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func stripCodexManagedConfig(from raw: String) -> String {
        var output: [String] = []
        var skippingModelProviderTable = false
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[model_providers.\(codexManagedProviderKey)]" {
                skippingModelProviderTable = true
                continue
            }
            if skippingModelProviderTable, trimmed.hasPrefix("[") {
                skippingModelProviderTable = false
            }
            if skippingModelProviderTable { continue }
            if let activeProvider = rootTomlValue(named: "model_provider", in: raw),
               activeProvider == codexManagedProviderKey,
               trimmed.hasPrefix("model_provider") {
                continue
            }
            output.append(line)
        }
        return output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func codexAuthStatus(authURL: URL) -> CodexAuthStatus {
        guard FileManager.default.fileExists(atPath: authURL.path),
              let data = try? Data(contentsOf: authURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let authMode = object["auth_mode"] as? String,
              authMode.caseInsensitiveCompare("chatgpt") == .orderedSame,
              let tokens = object["tokens"] as? [String: Any],
              tokensHaveLoginSecret(tokens) else {
            return CodexAuthStatus(
                authenticated: false,
                source: "",
                accountLabel: nil,
                message: "未检测到 Codex/ChatGPT 官方登录状态，请先在 Codex 中完成官方登录。"
            )
        }

        return CodexAuthStatus(
            authenticated: true,
            source: authURL.path,
            accountLabel: accountLabel(from: tokens),
            message: "已检测到 Codex/ChatGPT 官方登录状态。"
        )
    }

    private static func tokensHaveLoginSecret(_ tokens: [String: Any]) -> Bool {
        ["access_token", "id_token", "refresh_token"].contains { key in
            guard let value = tokens[key] as? String else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func accountLabel(from tokens: [String: Any]) -> String? {
        for key in ["id_token", "access_token"] {
            guard let token = tokens[key] as? String,
                  let label = accountLabel(fromJWT: token) else { continue }
            return label
        }
        return nil
    }

    private static func accountLabel(fromJWT token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count > 1,
              let data = base64URLDecode(String(parts[1])),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let email = object["email"] as? String, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return email.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let profile = object["https://api.openai.com/profile"] as? [String: Any],
           let email = profile["email"] as? String,
           !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return email.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let name = object["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var input = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while !input.count.isMultiple(of: 4) {
            input.append("=")
        }
        return Data(base64Encoded: input)
    }

    private static func rootTomlValue(named key: String, in raw: String) -> String? {
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { return nil }
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let (name, value) = splitTomlAssignment(trimmed), name == key else { continue }
            return unquoteTomlString(value)
        }
        return nil
    }

    private static func tomlTableValues(named table: String, in raw: String) -> [String: String]? {
        let header = "[\(table)]"
        var values: [String: String] = [:]
        var inTable = false
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if inTable { break }
                inTable = trimmed == header
                continue
            }
            guard inTable, !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                  let (key, value) = splitTomlAssignment(trimmed) else {
                continue
            }
            values[key] = value
        }
        return inTable ? values : nil
    }

    private static func splitTomlAssignment(_ line: String) -> (String, String)? {
        guard let separator = line.firstIndex(of: "=") else { return nil }
        let key = line[..<separator].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    private static func unquoteTomlString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }
}

private extension JSONEncoder {
    static var apiProviderEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var apiProviderDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
