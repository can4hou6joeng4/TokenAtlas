import Foundation
import Testing
@testable import TokenAtlas

@Suite("API provider switcher")
struct APIProviderSwitcherTests {
    @Test("Claude provider writes managed env and preserves non-provider settings")
    func claudeProviderPreservesNonProviderSettings() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let claudeConfig = temp.appendingPathComponent("Claude", isDirectory: true)
        let settingsURL = claudeConfig.appendingPathComponent("settings.json", isDirectory: false)
        try TempDir.write(
            """
            {
              "env" : {
                "ANTHROPIC_BASE_URL" : "https://old.example",
                "ANTHROPIC_API_KEY" : "old-key",
                "CUSTOM_ENV" : "keep-me"
              },
              "permissions" : {
                "allow" : ["Bash(ls)"]
              },
              "statusLine" : {
                "command" : "echo ok"
              }
            }
            """,
            to: settingsURL
        )

        let store = makeStore(temp: temp, claudeConfig: claudeConfig)
        let provider = CLIAPIProvider(
            id: "gateway",
            cli: .claude,
            name: "Gateway",
            baseURL: "https://gateway.example",
            apiKey: .inline("sk-gateway"),
            model: "claude-compatible"
        )

        _ = try await store.apply(provider: provider, currentActive: nil, keyStorageMode: .json)

        let object = try readJSONObject(settingsURL)
        let env = try #require(object["env"] as? [String: Any])
        #expect(env["ANTHROPIC_BASE_URL"] as? String == "https://gateway.example")
        #expect(env["ANTHROPIC_AUTH_TOKEN"] as? String == "sk-gateway")
        #expect(env["ANTHROPIC_API_KEY"] == nil)
        #expect(env["CUSTOM_ENV"] as? String == "keep-me")
        #expect(object["permissions"] != nil)
        #expect(object["statusLine"] != nil)
    }

    @Test("Codex provider writes hybrid relay while preserving auth and common config")
    func codexProviderPreservesCommonConfig() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let codexHome = temp.appendingPathComponent("Codex", isDirectory: true)
        let authJSON = #"{"auth_mode":"chatgpt","tokens":{"access_token":"header.eyJlbWFpbCI6InVzZXJAZXhhbXBsZS5jb20ifQ.signature"}}"#
        try TempDir.write(authJSON, to: codexHome.appendingPathComponent("auth.json"))
        try TempDir.write(
            """
            model_provider = "old"
            model = "old-model"

            [model_providers.old]
            name = "Old"
            base_url = "https://old.example"

            [mcp_servers.github]
            command = "gh"
            args = ["mcp", "server"]
            """,
            to: codexHome.appendingPathComponent("config.toml")
        )

        let store = makeStore(temp: temp, codexHome: codexHome)
        let provider = CLIAPIProvider(
            id: "openrouter",
            cli: .codex,
            name: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1",
            apiKey: .inline("sk-new"),
            model: "openai/gpt-oss"
        )

        _ = try await store.apply(provider: provider, currentActive: nil, keyStorageMode: .json)

        let auth = try String(contentsOf: codexHome.appendingPathComponent("auth.json"), encoding: .utf8)
        let config = try String(contentsOf: codexHome.appendingPathComponent("config.toml"), encoding: .utf8)
        #expect(auth == authJSON)
        #expect(config.contains(#"model_provider = "TokenAtlas""#))
        #expect(config.contains("[model_providers.TokenAtlas]"))
        #expect(config.contains(#"base_url = "https://openrouter.ai/api/v1""#))
        #expect(config.contains(#"requires_openai_auth = true"#))
        #expect(config.contains(#"experimental_bearer_token = "sk-new""#))
        #expect(config.contains("[model_providers.old]"))
        #expect(config.contains("[mcp_servers.github]"))
        #expect(config.contains(#"command = "gh""#))
        #expect(config.contains(#"model = "old-model""#))
    }

    @Test("Codex official channel clears only TokenAtlas managed provider")
    func codexOfficialChannelClearsOnlyTokenAtlasProvider() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let codexHome = temp.appendingPathComponent("Codex", isDirectory: true)
        let authJSON = #"{"auth_mode":"chatgpt","tokens":{"access_token":"header.eyJlbWFpbCI6InVzZXJAZXhhbXBsZS5jb20ifQ.signature"}}"#
        try TempDir.write(authJSON, to: codexHome.appendingPathComponent("auth.json"))
        try TempDir.write(
            """
            model_provider = "TokenAtlas"
            model = "gpt-5.5"

            [model_providers.TokenAtlas]
            name = "TokenAtlas"
            wire_api = "responses"
            requires_openai_auth = true
            base_url = "https://relay.example/v1"
            experimental_bearer_token = "sk-old"

            [model_providers.other]
            name = "Other"
            base_url = "https://other.example/v1"

            [mcp_servers.github]
            command = "gh"
            """,
            to: codexHome.appendingPathComponent("config.toml")
        )

        let store = makeStore(temp: temp, codexHome: codexHome)
        let official = ConfigurationProviderStore.officialProvider(for: .codex)

        _ = try await store.apply(provider: official, currentActive: nil, keyStorageMode: .json)

        let auth = try String(contentsOf: codexHome.appendingPathComponent("auth.json"), encoding: .utf8)
        let config = try String(contentsOf: codexHome.appendingPathComponent("config.toml"), encoding: .utf8)
        #expect(auth == authJSON)
        #expect(config.contains(#"model_provider = "TokenAtlas""#) == false)
        #expect(config.contains("[model_providers.TokenAtlas]") == false)
        #expect(config.contains("[model_providers.other]"))
        #expect(config.contains(#"base_url = "https://other.example/v1""#))
        #expect(config.contains(#"model = "gpt-5.5""#))
        #expect(config.contains("[mcp_servers.github]"))
    }

    @Test("Codex hybrid relay requires ChatGPT login")
    func codexHybridRelayRequiresChatGPTLogin() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let codexHome = temp.appendingPathComponent("Codex", isDirectory: true)
        try TempDir.write(#"{"OPENAI_API_KEY":"sk-api"}"#, to: codexHome.appendingPathComponent("auth.json"))
        try TempDir.write(
            """
            [mcp_servers.github]
            command = "gh"
            """,
            to: codexHome.appendingPathComponent("config.toml")
        )

        let store = makeStore(temp: temp, codexHome: codexHome)
        let provider = CLIAPIProvider(
            id: "relay",
            cli: .codex,
            name: "Relay",
            baseURL: "https://relay.example/v1",
            apiKey: .inline("sk-relay")
        )

        await #expect(throws: ConfigurationProviderStoreError.self) {
            _ = try await store.apply(provider: provider, currentActive: nil, keyStorageMode: .json)
        }

        let config = try String(contentsOf: codexHome.appendingPathComponent("config.toml"), encoding: .utf8)
        #expect(config.contains("[model_providers.TokenAtlas]") == false)
        #expect(config.contains("[mcp_servers.github]"))
    }

    @Test("Codex import current reads active relay bearer token")
    func codexImportCurrentReadsActiveRelayBearerToken() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let codexHome = temp.appendingPathComponent("Codex", isDirectory: true)
        try TempDir.write(#"{"auth_mode":"chatgpt","tokens":{"refresh_token":"refresh"}}"#, to: codexHome.appendingPathComponent("auth.json"))
        try TempDir.write(
            """
            model_provider = "CodexPilot"

            [model_providers.CodexPilot]
            name = "CodexPilot"
            wire_api = "responses"
            requires_openai_auth = true
            base_url = "https://codexpilot.example/v1"
            experimental_bearer_token = "sk-imported"
            """,
            to: codexHome.appendingPathComponent("config.toml")
        )

        let store = makeStore(temp: temp, codexHome: codexHome)
        let provider = try await store.importCurrentProvider(
            cli: .codex,
            name: "Default",
            id: "default",
            keyStorageMode: .json
        )

        #expect(provider.baseURL == "https://codexpilot.example/v1")
        #expect(provider.apiKey == .inline("sk-imported"))
    }

    @Test("Codex channel status uses selected TokenAtlas profile name")
    func codexChannelStatusUsesSelectedTokenAtlasProfileName() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let codexHome = temp.appendingPathComponent("Codex", isDirectory: true)
        try TempDir.write(
            #"{"auth_mode":"chatgpt","tokens":{"refresh_token":"refresh"}}"#,
            to: codexHome.appendingPathComponent("auth.json")
        )
        try TempDir.write(
            """
            model_provider = "TokenAtlas"

            [model_providers.TokenAtlas]
            name = "TokenAtlas"
            wire_api = "responses"
            requires_openai_auth = true
            base_url = "https://relay.example/v1"
            experimental_bearer_token = "sk-relay"
            """,
            to: codexHome.appendingPathComponent("config.toml")
        )

        let store = makeStore(temp: temp, codexHome: codexHome)
        let active = CLIAPIProvider(
            id: "relay",
            cli: .codex,
            name: "bobochang 中转",
            baseURL: "https://relay.example/v1",
            apiKey: .inline("sk-relay")
        )

        let status = await store.codexChannelStatus(activeProvider: active)

        #expect(status.channel == .hybridRelay)
        #expect(status.configured)
        #expect(status.activeProfileName == "bobochang 中转")
    }

    @Test("Import Current creates Default provider")
    func importCurrentCreatesDefaultProvider() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let claudeConfig = temp.appendingPathComponent("Claude", isDirectory: true)
        try TempDir.write(
            """
            {
              "env" : {
                "ANTHROPIC_BASE_URL" : "https://current.example",
                "ANTHROPIC_AUTH_TOKEN" : "sk-current",
                "ANTHROPIC_MODEL" : "current-model"
              }
            }
            """,
            to: claudeConfig.appendingPathComponent("settings.json")
        )

        let store = makeStore(temp: temp, claudeConfig: claudeConfig)
        let provider = try await store.importCurrentProvider(
            cli: .claude,
            name: "Default",
            id: "default",
            keyStorageMode: .json
        )

        #expect(provider.id == "default")
        #expect(provider.origin.kind == .importedDefault)
        #expect(provider.name == "Default")
        #expect(provider.baseURL == "https://current.example")
        #expect(provider.apiKey == .inline("sk-current"))
        #expect(provider.model == "current-model")
    }

    @MainActor
    @Test("Codex reload does not preload conversation maintenance")
    func codexReloadDoesNotPreloadConversationMaintenance() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let store = makeStore(temp: temp)
        let maintenance = CountingCodexConversationMaintenance()
        let vm = APIProviderSwitcherViewModel(store: store, conversationMaintenance: maintenance)

        await vm.reload(keyStorageMode: .json)

        #expect(await maintenance.providerSyncPreviewCount == 0)
        #expect(await maintenance.recycleBinSnapshotCount == 0)

        await vm.loadConversationMaintenanceIfNeeded()

        #expect(await maintenance.providerSyncPreviewCount == 1)
        #expect(await maintenance.recycleBinSnapshotCount == 1)
    }

    @MainActor
    @Test("Configuration reload does not auto-import current providers into Keychain")
    func configurationReloadDoesNotAutoImportCurrentProvidersIntoKeychain() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let claudeConfig = temp.appendingPathComponent("Claude", isDirectory: true)
        try TempDir.write(
            """
            {
              "env" : {
                "ANTHROPIC_BASE_URL" : "https://current-claude.example",
                "ANTHROPIC_AUTH_TOKEN" : "sk-current-claude"
              }
            }
            """,
            to: claudeConfig.appendingPathComponent("settings.json")
        )

        let codexHome = temp.appendingPathComponent("Codex", isDirectory: true)
        try TempDir.write(
            #"{"auth_mode":"chatgpt","tokens":{"refresh_token":"refresh"}}"#,
            to: codexHome.appendingPathComponent("auth.json")
        )
        try TempDir.write(
            """
            model_provider = "TokenAtlas"

            [model_providers.TokenAtlas]
            name = "TokenAtlas"
            wire_api = "responses"
            requires_openai_auth = true
            base_url = "https://current-codex.example/v1"
            experimental_bearer_token = "sk-current-codex"
            """,
            to: codexHome.appendingPathComponent("config.toml")
        )

        let secretStore = CountingAPIProviderSecretStore()
        let store = makeStore(temp: temp, claudeConfig: claudeConfig, codexHome: codexHome, secretStore: secretStore)
        let vm = APIProviderSwitcherViewModel(store: store)

        await vm.reload(keyStorageMode: .keychain)

        #expect(vm.providers(for: .claude).map(\.id) == ["official"])
        #expect(vm.providers(for: .codex).map(\.id) == ["official"])
        #expect(vm.activeProvider(for: .claude) == nil)
        #expect(vm.activeProvider(for: .codex) == nil)
        #expect(secretStore.readCount == 0)
        #expect(secretStore.saveCount == 0)
    }

    @MainActor
    @Test("Refreshing Codex channel status does not override in-progress UI selection")
    func refreshCodexStatusDoesNotOverrideInteractiveSelection() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let codexHome = temp.appendingPathComponent("Codex", isDirectory: true)
        try TempDir.write(
            #"{"auth_mode":"chatgpt","tokens":{"refresh_token":"refresh"}}"#,
            to: codexHome.appendingPathComponent("auth.json")
        )
        try TempDir.write("", to: codexHome.appendingPathComponent("config.toml"))

        let store = makeStore(temp: temp, codexHome: codexHome)
        let vm = APIProviderSwitcherViewModel(store: store)

        await vm.reload(keyStorageMode: .json)
        vm.selectCodexChannel(.hybridRelay, keyStorageMode: .json)
        await vm.refreshCodexChannelStatus()

        #expect(vm.codexChannelStatus.channel == .official)
        #expect(vm.selectedCodexChannel == .hybridRelay)
    }

    @MainActor
    @Test("Applying Codex hybrid relay does not preload conversation maintenance")
    func applyingCodexHybridRelayDoesNotPreloadConversationMaintenance() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let codexHome = temp.appendingPathComponent("Codex", isDirectory: true)
        try TempDir.write(
            #"{"auth_mode":"chatgpt","tokens":{"refresh_token":"refresh"}}"#,
            to: codexHome.appendingPathComponent("auth.json")
        )
        try TempDir.write("", to: codexHome.appendingPathComponent("config.toml"))

        let store = makeStore(temp: temp, codexHome: codexHome)
        let maintenance = CountingCodexConversationMaintenance()
        let vm = APIProviderSwitcherViewModel(store: store, conversationMaintenance: maintenance)

        await vm.reload(keyStorageMode: .json)
        await vm.addCodexProfile(keyStorageMode: .json)
        vm.draftName = "Relay"
        vm.draftBaseURL = "https://relay.example/v1"
        vm.draftAPIKey = "sk-relay"

        await vm.saveAndApplyCodexProfile(keyStorageMode: .json)

        #expect(vm.selectedCodexChannel == .hybridRelay)
        #expect(await maintenance.providerSyncPreviewCount == 0)
        #expect(await maintenance.recycleBinSnapshotCount == 0)
        #expect(vm.maintenanceMessage == "混合中转已应用。需要同步历史对话归属时，请展开对话维护。")
    }

    @MainActor
    @Test("Switching CLI tabs opens guided Claude mode without Keychain read")
    func switchingCLITabsOpensGuidedClaudeModeWithoutKeychainRead() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let secretStore = CountingAPIProviderSecretStore()
        secretStore.saveAPIKey("sk-claude", account: "claude-provider")
        let store = makeStore(temp: temp, secretStore: secretStore)
        let claude = CLIAPIProvider(
            id: "claude-relay",
            cli: .claude,
            origin: .appSpecific,
            name: "Claude Relay",
            baseURL: "https://claude.example",
            apiKey: .keychain(account: "claude-provider"),
            model: "claude-model"
        )
        let defaultClaude = CLIAPIProvider(
            id: "default",
            cli: .claude,
            origin: .importedDefault,
            name: "Default"
        )
        try await store.saveLibrary(ConfigurationProviderLibrary(
            cliProviders: [defaultClaude, claude],
            activeProviderIDs: [.claude: claude.id, .codex: "official"]
        ))
        let vm = APIProviderSwitcherViewModel(store: store)

        await vm.reload(keyStorageMode: .keychain)
        vm.selectCLI(.codex, keyStorageMode: .keychain)
        vm.selectCLI(.claude, keyStorageMode: .keychain)

        #expect(vm.selectedCLI == .claude)
        #expect(vm.selectedClaudeMode == .official)
        #expect(vm.selectedProviderID == nil)
        #expect(vm.draftProviderID == nil)
        #expect(vm.draftAPIKey == "")
        #expect(!vm.isDraftDetailLoading)
        #expect(secretStore.readCount == 0)

        vm.selectClaudeMode(.customSettings, keyStorageMode: .keychain)

        #expect(vm.selectedProviderID == claude.id)
        #expect(vm.draftProviderID == claude.id)
        #expect(vm.draftAPIKey == "")
        #expect(vm.isDraftDetailLoading)
        #expect(secretStore.readCount == 0)

        await vm.loadSelectedDraftDetailsIfNeeded()

        #expect(vm.draftAPIKey == "sk-claude")
        #expect(vm.draftRawConfig.contains("claude.example"))
        #expect(!vm.isDraftDetailLoading)
        #expect(secretStore.readCount == 1)
    }

    @MainActor
    @Test("Switching to Claude opens guided official mode without Keychain read")
    func switchingToClaudeOpensGuidedOfficialModeWithoutKeychainRead() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let secretStore = CountingAPIProviderSecretStore()
        secretStore.saveAPIKey("sk-claude", account: "claude-provider")
        let store = makeStore(temp: temp, secretStore: secretStore)
        let claude = CLIAPIProvider(
            id: "claude-relay",
            cli: .claude,
            origin: .appSpecific,
            name: "Claude Relay",
            baseURL: "https://relay.example",
            apiKey: .keychain(account: "claude-provider")
        )
        let defaultClaude = CLIAPIProvider(
            id: "default",
            cli: .claude,
            origin: .importedDefault,
            name: "Default"
        )
        try await store.saveLibrary(ConfigurationProviderLibrary(
            cliProviders: [
                ConfigurationProviderStore.officialProvider(for: .codex),
                defaultClaude,
                claude,
            ],
            activeProviderIDs: [.claude: claude.id, .codex: "official"]
        ))
        let vm = APIProviderSwitcherViewModel(store: store)

        await vm.reload(keyStorageMode: .keychain)
        vm.selectCLI(.codex, keyStorageMode: .keychain)
        vm.selectCLI(.claude, keyStorageMode: .keychain)

        #expect(vm.selectedCLI == .claude)
        #expect(vm.selectedClaudeMode == .official)
        #expect(vm.selectedProviderID == nil)
        #expect(vm.draftProviderID == nil)
        #expect(!vm.isDraftDetailLoading)
        #expect(secretStore.readCount == 0)

        vm.selectClaudeMode(.customSettings, keyStorageMode: .keychain)

        #expect(vm.selectedProviderID == claude.id)
        #expect(vm.draftProviderID == claude.id)
        #expect(vm.isDraftDetailLoading)
        #expect(secretStore.readCount == 0)
    }

    @MainActor
    @Test("Claude settings variants are discovered and imported without modifying source files")
    func claudeSettingsVariantsImportWithoutModifyingSourceFiles() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let claudeConfig = temp.appendingPathComponent("Claude", isDirectory: true)
        let anyrouterURL = claudeConfig.appendingPathComponent("settings.anyrouter.json")
        let deepseekURL = claudeConfig.appendingPathComponent("settings.deepseek.json")
        let localURL = claudeConfig.appendingPathComponent("settings.local.json")
        let securityURL = claudeConfig.appendingPathComponent("security_warnings_state_test.json")
        let anyrouterRaw = #"{ "env" : { "ANTHROPIC_BASE_URL" : "https://anyrouter.example", "ANTHROPIC_AUTH_TOKEN" : "sk-anyrouter" } }"#
        let deepseekRaw = #"{ "env" : { "ANTHROPIC_BASE_URL" : "https://deepseek.example", "ANTHROPIC_DEFAULT_OPUS_MODEL" : "deepseek-model" } }"#
        try TempDir.write(anyrouterRaw, to: anyrouterURL)
        try TempDir.write(deepseekRaw, to: deepseekURL)
        try TempDir.write(#"{ "env" : { "ANTHROPIC_BASE_URL" : "https://local.example" } }"#, to: localURL)
        try TempDir.write(#"{ "seen" : true }"#, to: securityURL)

        let store = makeStore(temp: temp, claudeConfig: claudeConfig)
        let vm = APIProviderSwitcherViewModel(store: store)

        await vm.reload(keyStorageMode: .json)
        await vm.loadClaudeSettingsCandidates()

        #expect(vm.claudeSettingsCandidates.map(\.url.lastPathComponent) == ["settings.anyrouter.json", "settings.deepseek.json"])
        let anyrouter = try #require(vm.claudeSettingsCandidates.first { $0.label == "anyrouter" })
        #expect(anyrouter.commandPreview.contains("claude --settings"))

        await vm.importClaudeSettingsCandidate(anyrouter, keyStorageMode: .json)

        let imported = try #require(vm.providers(for: .claude).first { $0.id == "claude-settings-anyrouter" })
        #expect(imported.name == "Anyrouter")
        #expect(imported.baseURL == "https://anyrouter.example")
        #expect(imported.apiKey == .inline("sk-anyrouter"))
        #expect(try String(contentsOf: anyrouterURL, encoding: .utf8) == anyrouterRaw)
        #expect(try String(contentsOf: deepseekURL, encoding: .utf8) == deepseekRaw)
    }

    @MainActor
    @Test("Enable Provider backs up live files and updates active id")
    func enableProviderBacksUpAndUpdatesActiveID() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let claudeConfig = temp.appendingPathComponent("Claude", isDirectory: true)
        try TempDir.write(#"{ "env" : { "ANTHROPIC_BASE_URL" : "https://default.example" } }"#, to: claudeConfig.appendingPathComponent("settings.json"))
        let store = makeStore(temp: temp, claudeConfig: claudeConfig)
        let vm = APIProviderSwitcherViewModel(store: store)

        await vm.reload(keyStorageMode: .json)
        await vm.addProvider(keyStorageMode: .json)
        vm.draftName = "Gateway"
        vm.draftBaseURL = "https://gateway.example"
        vm.draftAPIKey = "sk-gateway"
        vm.draftModel = "gateway-model"

        await vm.enableSelectedProvider(rawMode: false, keyStorageMode: .json)

        let active = try #require(vm.activeProvider(for: .claude))
        #expect(active.name == "Gateway")
        #expect(vm.latestApplyResult != nil)
        if let backup = vm.latestApplyResult?.backupDirectory {
            #expect(FileManager.default.fileExists(atPath: backup.appendingPathComponent("manifest.json").path))
        }
        let settings = try readJSONObject(claudeConfig.appendingPathComponent("settings.json"))
        let env = try #require(settings["env"] as? [String: Any])
        #expect(env["ANTHROPIC_BASE_URL"] as? String == "https://gateway.example")
    }

    @Test("Universal provider generates Claude and Codex child providers")
    func universalProviderGeneratesChildren() throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let store = makeStore(temp: temp)
        let (universal, initialChildren) = store.makeUniversalProvider(keyStorageMode: .json)
        #expect(Set(initialChildren.map(\.cli)) == Set(APIProviderCLI.allCases))

        let saved = try store.universalBySavingDraft(
            existing: universal,
            editedCLI: .claude,
            name: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1",
            apiKey: "sk-universal",
            model: "anthropic/claude-compatible",
            keyStorageMode: .json
        )
        let children = store.childProviders(for: saved, keyStorageMode: .json)
        let claude = try #require(children.first { $0.cli == .claude })
        let codex = try #require(children.first { $0.cli == .codex })
        #expect(claude.name == "OpenRouter")
        #expect(codex.name == "OpenRouter")
        #expect(claude.baseURL == "https://openrouter.ai/api/v1")
        #expect(codex.baseURL == "https://openrouter.ai/api/v1")
        #expect(claude.model == "anthropic/claude-compatible")
        #expect(codex.model == "gpt-5.4")
        #expect(claude.apiKey == .inline("sk-universal"))
        #expect(codex.apiKey == .inline("sk-universal"))
    }

    @Test("JSON and Keychain API key storage resolve the same key")
    func apiKeyStorageModesResolveKeys() throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let secretStore = InMemoryAPIProviderSecretStore()
        let store = makeStore(temp: temp, secretStore: secretStore)
        let existing = CLIAPIProvider(id: "provider", cli: .claude, name: "Provider")

        let jsonProvider = try store.providerBySavingDraft(
            existing: existing,
            name: "Provider",
            category: .custom,
            baseURL: "https://json.example",
            apiKey: "sk-json",
            model: "json-model",
            rawConfig: "",
            rawMode: false,
            keyStorageMode: .json
        )
        let keychainProvider = try store.providerBySavingDraft(
            existing: existing,
            name: "Provider",
            category: .custom,
            baseURL: "https://keychain.example",
            apiKey: "sk-keychain",
            model: "keychain-model",
            rawConfig: "",
            rawMode: false,
            keyStorageMode: .keychain
        )

        #expect(jsonProvider.apiKey == .inline("sk-json"))
        if case .keychain(let account) = keychainProvider.apiKey {
            #expect(secretStore.readAPIKey(account: account) == "sk-keychain")
        } else {
            Issue.record("Expected keychain provider secret")
        }
        #expect(store.resolvedAPIKey(for: jsonProvider.apiKey) == "sk-json")
        #expect(store.resolvedAPIKey(for: keychainProvider.apiKey) == "sk-keychain")
    }

    @MainActor
    @Test("Deleting a Keychain provider removes its stored key")
    func deletingKeychainProviderRemovesStoredKey() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let secretStore = InMemoryAPIProviderSecretStore()
        secretStore.saveAPIKey("sk-old", account: "claude-provider")
        let store = makeStore(temp: temp, secretStore: secretStore)
        let provider = CLIAPIProvider(
            id: "provider",
            cli: .claude,
            origin: .appSpecific,
            name: "Provider",
            apiKey: .keychain(account: "claude-provider")
        )
        try await store.saveLibrary(ConfigurationProviderLibrary(cliProviders: [provider]))
        let vm = APIProviderSwitcherViewModel(store: store)

        await vm.reload(keyStorageMode: .keychain)
        let loadedProvider = try #require(vm.providers(for: .claude).first { $0.id == "provider" })
        vm.selectProvider(loadedProvider, keyStorageMode: .keychain)

        await vm.deleteSelectedProvider(keyStorageMode: .keychain)

        #expect(secretStore.readAPIKey(account: "claude-provider") == nil)
        #expect(vm.providers(for: .claude).contains { $0.id == "provider" } == false)
    }

    @MainActor
    @Test("Provider list cache invalidates after library mutation")
    func providerListCacheInvalidatesAfterMutation() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let store = makeStore(temp: temp)
        let vm = APIProviderSwitcherViewModel(store: store)

        await vm.reload(keyStorageMode: .json)
        let initial = vm.providers(for: .claude)
        #expect(vm.providers(for: .claude).map(\.id) == initial.map(\.id))

        await vm.addProvider(keyStorageMode: .json)

        let selectedID = try #require(vm.selectedProviderID)
        let updated = vm.providers(for: .claude)
        #expect(updated.count == initial.count + 1)
        #expect(updated.contains { $0.id == selectedID })
    }

    @MainActor
    @Test("Switching a provider away from Keychain removes the old stored key")
    func switchingProviderAwayFromKeychainRemovesOldStoredKey() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let secretStore = InMemoryAPIProviderSecretStore()
        secretStore.saveAPIKey("sk-old", account: "claude-provider")
        let store = makeStore(temp: temp, secretStore: secretStore)
        let provider = CLIAPIProvider(
            id: "provider",
            cli: .claude,
            origin: .appSpecific,
            name: "Provider",
            apiKey: .keychain(account: "claude-provider")
        )
        try await store.saveLibrary(ConfigurationProviderLibrary(cliProviders: [provider]))
        let vm = APIProviderSwitcherViewModel(store: store)

        await vm.reload(keyStorageMode: .keychain)
        let loadedProvider = try #require(vm.providers(for: .claude).first { $0.id == "provider" })
        vm.selectProvider(loadedProvider, keyStorageMode: .keychain)
        vm.draftAPIKey = "sk-json"

        let saved = await vm.saveDraft(rawMode: false, keyStorageMode: .json)

        let updatedProvider = try #require(vm.providers(for: .claude).first { $0.id == "provider" })
        #expect(saved)
        #expect(updatedProvider.apiKey == .inline("sk-json"))
        #expect(secretStore.readAPIKey(account: "claude-provider") == nil)
    }

    @Test("Provider library persists CLI-keyed maps as string dictionaries")
    func providerLibraryPersistsCLIMaps() async throws {
        let temp = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: temp) }

        let store = makeStore(temp: temp)
        let universal = UniversalAPIProvider(
            id: "u",
            name: "Universal",
            modelOverrides: [.claude: "claude-model", .codex: "codex-model"]
        )
        let library = ConfigurationProviderLibrary(
            universalProviders: [universal],
            activeProviderIDs: [.claude: "default", .codex: "official"],
            commonConfigByCLI: [.codex: "[mcp_servers.github]"]
        )

        try await store.saveLibrary(library)

        let raw = try String(
            contentsOf: temp
                .appendingPathComponent("ProviderLibrary", isDirectory: true)
                .appendingPathComponent("providers.json", isDirectory: false),
            encoding: .utf8
        )
        #expect(raw.contains(#""claude" : "default""#))
        #expect(raw.contains(#""codex" : "official""#))
        #expect(raw.contains(#""claude" : "claude-model""#))
        #expect(raw.contains(#""codex" : "codex-model""#))

        let loaded = try await store.loadLibrary()
        #expect(loaded.activeProviderIDs[.claude] == "default")
        #expect(loaded.activeProviderIDs[.codex] == "official")
        #expect(loaded.universalProviders.first?.modelOverrides[.claude] == "claude-model")
        #expect(loaded.universalProviders.first?.modelOverrides[.codex] == "codex-model")
    }

    private func makeStore(
        temp: URL,
        claudeConfig: URL? = nil,
        codexHome: URL? = nil,
        secretStore: any APIProviderSecretStoring = InMemoryAPIProviderSecretStore()
    ) -> ConfigurationProviderStore {
        ConfigurationProviderStore(
            rootDirectory: temp.appendingPathComponent("ProviderLibrary", isDirectory: true),
            claudePaths: ClaudePaths(configDirectory: claudeConfig ?? temp.appendingPathComponent("Claude", isDirectory: true)),
            codexPaths: CodexPaths(homeDirectory: codexHome ?? temp.appendingPathComponent("Codex", isDirectory: true)),
            secretStore: secretStore
        )
    }

    private func readJSONObject(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private final class CountingAPIProviderSecretStore: APIProviderSecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var reads = 0
    private var saves = 0

    var readCount: Int {
        lock.withLock { reads }
    }

    var saveCount: Int {
        lock.withLock { saves }
    }

    func readAPIKey(account: String) -> String? {
        lock.withLock {
            reads += 1
            return values[account]
        }
    }

    func saveAPIKey(_ apiKey: String, account: String) {
        lock.withLock {
            saves += 1
            values[account] = apiKey
        }
    }

    func deleteAPIKey(account: String) {
        lock.withLock { _ = values.removeValue(forKey: account) }
    }
}

private actor CountingCodexConversationMaintenance: CodexConversationMaintaining {
    private var providerSyncPreviews = 0
    private var recycleBinSnapshots = 0

    var providerSyncPreviewCount: Int { providerSyncPreviews }
    var recycleBinSnapshotCount: Int { recycleBinSnapshots }

    func providerSyncSnapshot(targetProvider: String?) async throws -> CodexProviderSyncSnapshot {
        providerSyncPreviews += 1
        return CodexProviderSyncSnapshot(
            targetProvider: targetProvider ?? ConfigurationProviderStore.codexManagedProviderKey,
            currentProvider: "openai",
            availableProviders: [ConfigurationProviderStore.codexManagedProviderKey],
            rolloutFiles: 0,
            rolloutRewriteNeeded: 0,
            sqliteRows: 0,
            sqliteProviderRowsNeedingSync: 0,
            rolloutProviders: [],
            sqliteProviders: []
        )
    }

    func runProviderSync(targetProvider: String) async throws -> CodexProviderSyncResult {
        CodexProviderSyncResult(
            targetProvider: targetProvider,
            rolloutFilesRewritten: 0,
            sqliteRowsUpdated: 0,
            backupDirectory: nil
        )
    }

    func recycleBinSnapshot() async throws -> CodexRecycleBinSnapshot {
        recycleBinSnapshots += 1
        return CodexRecycleBinSnapshot(entries: [])
    }

    func restoreRecycleBinEntries(tokens: [String]) async throws -> CodexRecycleBinBatchResult {
        CodexRecycleBinBatchResult(message: "", succeededTokens: [], failed: [])
    }

    func deleteRecycleBinEntries(tokens: [String]) async throws -> CodexRecycleBinBatchResult {
        CodexRecycleBinBatchResult(message: "", succeededTokens: [], failed: [])
    }
}
