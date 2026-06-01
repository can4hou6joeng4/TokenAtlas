import Foundation
import Observation

@MainActor
@Observable
final class APIProviderSwitcherViewModel {
    private let store: ConfigurationProviderStore
    private let conversationMaintenance: any CodexConversationMaintaining
    private var isOpeningDraft = false
    private var draftDetailGeneration = 0
    @ObservationIgnored private var sortedProvidersByCLI: [APIProviderCLI: [CLIAPIProvider]] = [:]

    private(set) var library = ConfigurationProviderLibrary() {
        didSet { sortedProvidersByCLI.removeAll() }
    }
    private(set) var isLoaded = false
    private(set) var isWorking = false
    private(set) var isDraftDetailLoading = false
    private(set) var lastError: String?
    private(set) var latestApplyResult: ConfigurationProviderApplyResult?
    private(set) var providerSyncSnapshot: CodexProviderSyncSnapshot?
    private(set) var providerSyncResult: CodexProviderSyncResult?
    private(set) var recycleBinSnapshot = CodexRecycleBinSnapshot(entries: [])
    private(set) var recycleBinResult: CodexRecycleBinBatchResult?
    private(set) var maintenanceMessage: String?
    private(set) var isMaintenanceLoading = false
    private(set) var isProviderSyncRunning = false
    private(set) var isRecycleBinActionRunning = false
    private(set) var claudeSettingsCandidates: [ClaudeSettingsCandidate] = []
    private(set) var isLoadingClaudeSettingsCandidates = false
    var providerSyncTarget = ConfigurationProviderStore.codexManagedProviderKey
    var customProviderSyncTarget = ""
    var useCustomProviderSyncTarget = false
    var selectedRecycleBinTokens = Set<String>()
    private(set) var codexChannelStatus = CodexChannelStatus(
        channel: .official,
        configPath: "",
        authPath: "",
        configured: false,
        authenticated: false,
        accountLabel: nil,
        activeProfileName: "官方通道"
    )

    var selectedCLI: APIProviderCLI = .claude
    var selectedProviderID: String?
    var selectedCodexChannel: CodexModelChannel = .official
    var selectedClaudeMode: ClaudeProviderMode = .official

    var draftProviderID: String?
    var draftCLI: APIProviderCLI = .claude
    var draftOrigin: APIProviderOrigin?
    var draftName = "" { didSet { markDraftDirty(oldValue, draftName) } }
    var draftCategory: APIProviderCategory = .custom { didSet { markDraftDirty(oldValue, draftCategory) } }
    var draftBaseURL = "" { didSet { markDraftDirty(oldValue, draftBaseURL) } }
    var draftAPIKey = "" { didSet { markDraftDirty(oldValue, draftAPIKey) } }
    var draftModel = "" { didSet { markDraftDirty(oldValue, draftModel) } }
    var draftRawConfig = "" { didSet { markDraftDirty(oldValue, draftRawConfig) } }
    var draftIsDirty = false

    init(
        store: ConfigurationProviderStore = ConfigurationProviderStore(),
        conversationMaintenance: any CodexConversationMaintaining = CodexConversationMaintenanceService()
    ) {
        self.store = store
        self.conversationMaintenance = conversationMaintenance
    }

    func loadIfNeeded(keyStorageMode: APIProviderKeyStorageMode) async {
        guard !isLoaded else {
            normalizeSelection(keyStorageMode: keyStorageMode)
            return
        }
        await reload(keyStorageMode: keyStorageMode)
    }

    func reload(keyStorageMode: APIProviderKeyStorageMode) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let loaded = try await store.loadLibrary()
            let ensured = try await store.ensureSystemProviders(in: loaded, keyStorageMode: keyStorageMode)
            library = ensured
            if ensured != loaded {
                try await store.saveLibrary(ensured)
            }
            isLoaded = true
            normalizeSelection(keyStorageMode: keyStorageMode)
            await refreshCodexChannelStatus(syncSelection: true)
        } catch {
            setError(error)
        }
    }

    func providers(for cli: APIProviderCLI) -> [CLIAPIProvider] {
        if let cached = sortedProvidersByCLI[cli] {
            return cached
        }

        let providers = library.cliProviders
            .filter { $0.cli == cli }
            .sorted { lhs, rhs in
                let lhsRank = Self.sortRank(lhs)
                let rhsRank = Self.sortRank(rhs)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        sortedProvidersByCLI[cli] = providers
        return providers
    }

    func activeProvider(for cli: APIProviderCLI) -> CLIAPIProvider? {
        guard let id = library.activeProviderIDs[cli] else { return nil }
        return provider(cli: cli, id: id)
    }

    func isActive(_ provider: CLIAPIProvider) -> Bool {
        library.activeProviderIDs[provider.cli] == provider.id
    }

    var codexProfiles: [CLIAPIProvider] {
        providers(for: .codex).filter { $0.origin.kind != .official }
    }

    var claudeProfiles: [CLIAPIProvider] {
        providers(for: .claude).filter { $0.origin.kind != .official }
    }

    var selectedCodexProfile: CLIAPIProvider? {
        guard let selectedProviderID else { return nil }
        return provider(cli: .codex, id: selectedProviderID)
    }

    var selectedClaudeProfile: CLIAPIProvider? {
        guard let selectedProviderID else { return nil }
        return provider(cli: .claude, id: selectedProviderID)
    }

    var selectedProvider: CLIAPIProvider? {
        guard let selectedProviderID else { return nil }
        return provider(cli: selectedCLI, id: selectedProviderID)
    }

    var canSaveSelectedProvider: Bool {
        draftOrigin?.kind != .official && draftProviderID != nil
    }

    var canDeleteSelectedProvider: Bool {
        guard let provider = selectedProvider else { return false }
        return !provider.isSystemProvider && !isActive(provider)
    }

    func selectCLI(_ cli: APIProviderCLI, keyStorageMode: APIProviderKeyStorageMode) {
        selectedCLI = cli
        selectedProviderID = nil
        switch cli {
        case .claude:
            selectedClaudeMode = .official
            clearDraft()
        case .codex:
            normalizeSelection(keyStorageMode: keyStorageMode)
            selectedCodexChannel = codexChannelStatus.channel
        }
    }

    func selectProvider(_ provider: CLIAPIProvider, keyStorageMode: APIProviderKeyStorageMode) {
        selectedCLI = provider.cli
        selectedProviderID = provider.id
        openDraft(provider, keyStorageMode: keyStorageMode)
        if provider.cli == .claude && provider.origin.kind != .official {
            selectedClaudeMode = .customSettings
        } else if provider.cli == .codex && provider.origin.kind != .official {
            selectedCodexChannel = .hybridRelay
        }
    }

    func selectClaudeMode(_ mode: ClaudeProviderMode, keyStorageMode: APIProviderKeyStorageMode) {
        selectedCLI = .claude
        selectedClaudeMode = mode
        switch mode {
        case .official:
            selectedProviderID = nil
            clearDraft()
        case .customSettings:
            let preferredID = library.activeProviderIDs[.claude].flatMap { id in
                provider(cli: .claude, id: id)?.origin.kind == .official ? nil : id
            } ?? claudeProfiles.first?.id
            selectedProviderID = preferredID
            if let preferredID, let profile = provider(cli: .claude, id: preferredID) {
                openDraft(profile, keyStorageMode: keyStorageMode)
            } else {
                clearDraft()
            }
        }
    }

    func selectCodexChannel(_ channel: CodexModelChannel, keyStorageMode: APIProviderKeyStorageMode) {
        selectedCLI = .codex
        selectedCodexChannel = channel
        switch channel {
        case .official:
            if let official = provider(cli: .codex, id: "official") {
                selectedProviderID = official.id
                openDraft(official, keyStorageMode: keyStorageMode)
            } else {
                selectedProviderID = nil
                clearDraft()
            }
        case .hybridRelay:
            let preferredID = library.activeProviderIDs[.codex].flatMap { id in
                provider(cli: .codex, id: id)?.origin.kind == .official ? nil : id
            } ?? codexProfiles.first?.id
            selectedProviderID = preferredID
            if let preferredID, let profile = provider(cli: .codex, id: preferredID) {
                openDraft(profile, keyStorageMode: keyStorageMode)
            } else {
                clearDraft()
            }
        }
    }

    func addProvider(keyStorageMode: APIProviderKeyStorageMode) async {
        if selectedCLI == .claude {
            selectedClaudeMode = .customSettings
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let provider = store.makeCustomProvider(cli: selectedCLI, keyStorageMode: keyStorageMode)
            library.cliProviders.append(provider)
            try await store.saveLibrary(library)
            selectedProviderID = provider.id
            openDraft(provider, keyStorageMode: keyStorageMode)
        } catch {
            setError(error)
        }
    }

    func addCodexProfile(keyStorageMode: APIProviderKeyStorageMode) async {
        selectedCLI = .codex
        selectedCodexChannel = .hybridRelay
        isWorking = true
        defer { isWorking = false }
        do {
            var provider = store.makeCustomProvider(cli: .codex, keyStorageMode: keyStorageMode)
            provider.name = "新中转"
            provider.model = ""
            provider.rawConfig = store.renderRawConfig(for: provider)
            library.cliProviders.append(provider)
            try await store.saveLibrary(library)
            selectedProviderID = provider.id
            openDraft(provider, keyStorageMode: keyStorageMode)
        } catch {
            setError(error)
        }
    }

    func addUniversalProvider(keyStorageMode: APIProviderKeyStorageMode) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let (universal, children) = store.makeUniversalProvider(keyStorageMode: keyStorageMode)
            library.universalProviders.append(universal)
            library.cliProviders.append(contentsOf: children)
            try await store.saveLibrary(library)
            let selectedID = ConfigurationProviderStore.universalChildID(universalID: universal.id, cli: selectedCLI)
            selectedProviderID = selectedID
            if let provider = provider(cli: selectedCLI, id: selectedID) {
                openDraft(provider, keyStorageMode: keyStorageMode)
            }
        } catch {
            setError(error)
        }
    }

    func importCurrent(keyStorageMode: APIProviderKeyStorageMode) async {
        if selectedCLI == .claude {
            selectedClaudeMode = .customSettings
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let imported = try await store.importCurrentProvider(
                cli: selectedCLI,
                name: "Default",
                id: "default",
                keyStorageMode: keyStorageMode
            )
            replaceCLIProvider(imported)
            library.activeProviderIDs[selectedCLI] = imported.id
            try await store.saveLibrary(library)
            selectedProviderID = imported.id
            openDraft(imported, keyStorageMode: keyStorageMode)
        } catch {
            setError(error)
        }
    }

    func loadClaudeSettingsCandidates() async {
        guard claudeSettingsCandidates.isEmpty else { return }
        isLoadingClaudeSettingsCandidates = true
        defer { isLoadingClaudeSettingsCandidates = false }
        claudeSettingsCandidates = await store.claudeSettingsCandidates()
    }

    func importClaudeSettingsCandidate(
        _ candidate: ClaudeSettingsCandidate,
        keyStorageMode: APIProviderKeyStorageMode
    ) async {
        selectedCLI = .claude
        selectedClaudeMode = .customSettings
        isWorking = true
        defer { isWorking = false }
        do {
            let imported = try await store.importClaudeSettingsCandidate(candidate, keyStorageMode: keyStorageMode)
            replaceCLIProvider(imported)
            try await store.saveLibrary(library)
            selectedProviderID = imported.id
            openDraft(imported, keyStorageMode: keyStorageMode)
        } catch {
            setError(error)
        }
    }

    @discardableResult
    func saveDraft(rawMode: Bool, keyStorageMode: APIProviderKeyStorageMode) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            let saved = try await saveDraftThrowing(rawMode: rawMode, keyStorageMode: keyStorageMode)
            selectedProviderID = saved.id
            openDraft(saved, keyStorageMode: keyStorageMode)
            return true
        } catch {
            setError(error)
            return false
        }
    }

    func applyOfficialCodexChannel(keyStorageMode: APIProviderKeyStorageMode) async {
        selectedCLI = .codex
        selectedCodexChannel = .official
        isWorking = true
        defer { isWorking = false }
        do {
            let official = provider(cli: .codex, id: "official") ?? ConfigurationProviderStore.officialProvider(for: .codex)
            let current = activeProvider(for: .codex)
            let (result, backfilled) = try await store.apply(provider: official, currentActive: current, keyStorageMode: keyStorageMode)
            if let backfilled {
                replaceCLIProvider(backfilled)
            }
            replaceCLIProvider(official)
            library.activeProviderIDs[.codex] = official.id
            latestApplyResult = result
            try await store.saveLibrary(library)
            selectedProviderID = official.id
            openDraft(official, keyStorageMode: keyStorageMode)
            await refreshCodexChannelStatus()
        } catch {
            setError(error)
        }
    }

    func saveAndApplyCodexProfile(keyStorageMode: APIProviderKeyStorageMode) async {
        selectedCLI = .codex
        selectedCodexChannel = .hybridRelay
        isWorking = true
        defer { isWorking = false }
        do {
            let target = try await saveDraftThrowing(rawMode: false, keyStorageMode: keyStorageMode)
            let current = activeProvider(for: .codex)
            let (result, backfilled) = try await store.apply(provider: target, currentActive: current, keyStorageMode: keyStorageMode)
            if let backfilled {
                replaceCLIProvider(backfilled)
            }
            library.activeProviderIDs[.codex] = target.id
            latestApplyResult = result
            try await store.saveLibrary(library)
            selectedProviderID = target.id
            openDraft(target, keyStorageMode: keyStorageMode)
            await refreshCodexChannelStatus()
            maintenanceMessage = "混合中转已应用。需要同步历史对话归属时，请展开对话维护。"
        } catch {
            setError(error)
        }
    }

    func enableSelectedProvider(rawMode: Bool, keyStorageMode: APIProviderKeyStorageMode) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let target: CLIAPIProvider
            if draftIsDirty {
                target = try await saveDraftThrowing(rawMode: rawMode, keyStorageMode: keyStorageMode)
            } else {
                guard let selectedProvider else { throw ConfigurationProviderStoreError.providerNotFound }
                target = selectedProvider
            }

            let current = activeProvider(for: target.cli)
            let (result, backfilled) = try await store.apply(
                provider: target,
                currentActive: current,
                keyStorageMode: keyStorageMode
            )
            if let backfilled {
                replaceCLIProvider(backfilled)
            }
            library.activeProviderIDs[target.cli] = target.id
            latestApplyResult = result
            try await store.saveLibrary(library)
            selectedProviderID = target.id
            openDraft(target, keyStorageMode: keyStorageMode)
        } catch {
            setError(error)
        }
    }

    func deleteSelectedProvider(keyStorageMode: APIProviderKeyStorageMode) async {
        guard canDeleteSelectedProvider, let provider = selectedProvider else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let removedSecrets: [APIProviderSecret]
            if provider.origin.kind == .universal, let universalID = provider.origin.universalID {
                let removedUniversals = library.universalProviders.filter { $0.id == universalID }
                let removedChildren = library.cliProviders.filter { $0.origin.kind == .universal && $0.origin.universalID == universalID }
                removedSecrets = removedUniversals.map(\.apiKey) + removedChildren.map(\.apiKey)
                library.universalProviders.removeAll { $0.id == universalID }
                library.cliProviders.removeAll { $0.origin.kind == .universal && $0.origin.universalID == universalID }
            } else {
                let removedProviders = library.cliProviders.filter { $0.cli == provider.cli && $0.id == provider.id }
                removedSecrets = removedProviders.map(\.apiKey)
                library.cliProviders.removeAll { $0.cli == provider.cli && $0.id == provider.id }
            }
            try await store.saveLibrary(library)
            store.deleteStoredSecrets(removedSecrets, retainedIn: library)
            selectedProviderID = nil
            normalizeSelection(keyStorageMode: keyStorageMode)
        } catch {
            setError(error)
        }
    }

    func deleteSelectedCodexProfile(keyStorageMode: APIProviderKeyStorageMode) async {
        guard selectedCLI == .codex,
              selectedCodexChannel == .hybridRelay,
              let provider = selectedCodexProfile,
              !provider.isSystemProvider,
              codexProfiles.count > 1 else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let removedSecrets = [provider.apiKey]
            library.cliProviders.removeAll { $0.cli == .codex && $0.id == provider.id }
            if library.activeProviderIDs[.codex] == provider.id {
                library.activeProviderIDs[.codex] = codexProfiles.first { $0.id != provider.id }?.id
            }
            try await store.saveLibrary(library)
            store.deleteStoredSecrets(removedSecrets, retainedIn: library)
            selectedProviderID = library.activeProviderIDs[.codex] ?? codexProfiles.first?.id
            if let selectedProviderID, let next = self.provider(cli: .codex, id: selectedProviderID) {
                openDraft(next, keyStorageMode: keyStorageMode)
            } else {
                clearDraft()
            }
        } catch {
            setError(error)
        }
    }

    func resetDraft(keyStorageMode: APIProviderKeyStorageMode) {
        guard let selectedProvider else {
            clearDraft()
            return
        }
        openDraft(selectedProvider, keyStorageMode: keyStorageMode)
    }

    func loadSelectedDraftDetailsIfNeeded() async {
        guard let selectedProvider else { return }
        await loadDraftDetails(for: selectedProvider)
    }

    func clearError() {
        lastError = nil
    }

    func refreshCodexChannelStatus(syncSelection: Bool = false) async {
        codexChannelStatus = await store.codexChannelStatus(activeProvider: activeProvider(for: .codex))
        if syncSelection {
            selectedCodexChannel = codexChannelStatus.channel
        }
    }

    func loadConversationMaintenanceIfNeeded() async {
        guard providerSyncSnapshot == nil && recycleBinSnapshot.entries.isEmpty else { return }
        await refreshConversationMaintenance()
    }

    func refreshConversationMaintenance() async {
        isMaintenanceLoading = true
        defer { isMaintenanceLoading = false }
        await previewProviderSync()
        await refreshRecycleBin()
    }

    func selectProviderSyncTarget(_ target: String) {
        useCustomProviderSyncTarget = target == "__custom"
        if !useCustomProviderSyncTarget {
            providerSyncTarget = target
        }
    }

    var selectedProviderSyncTarget: String {
        let value = useCustomProviderSyncTarget ? customProviderSyncTarget : providerSyncTarget
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? ConfigurationProviderStore.codexManagedProviderKey : trimmed
    }

    var canRunProviderSync: Bool {
        !isProviderSyncRunning && (providerSyncSnapshot?.totalPendingUpdates ?? 0) > 0
    }

    var selectedRecycleBinEntries: [CodexRecycleBinEntry] {
        recycleBinSnapshot.entries.filter { selectedRecycleBinTokens.contains($0.token) }
    }

    var selectedRecoverableRecycleBinTokens: [String] {
        selectedRecycleBinEntries.filter(\.recoverable).map(\.token)
    }

    var allRecycleBinEntriesSelected: Bool {
        !recycleBinSnapshot.entries.isEmpty && selectedRecycleBinTokens.count == recycleBinSnapshot.entries.count
    }

    func previewProviderSync() async {
        isProviderSyncRunning = true
        defer { isProviderSyncRunning = false }
        do {
            let snapshot = try await conversationMaintenance.providerSyncSnapshot(targetProvider: selectedProviderSyncTarget)
            providerSyncSnapshot = snapshot
            providerSyncTarget = snapshot.targetProvider
            if !useCustomProviderSyncTarget {
                customProviderSyncTarget = ""
            }
            maintenanceMessage = "归属检查完成：预计更新 \(snapshot.totalPendingUpdates) 项。"
        } catch {
            setError(error)
        }
    }

    func runProviderSync() async {
        isProviderSyncRunning = true
        defer { isProviderSyncRunning = false }
        do {
            let result = try await conversationMaintenance.runProviderSync(targetProvider: selectedProviderSyncTarget)
            providerSyncResult = result
            maintenanceMessage = result.summary
            await previewProviderSync()
        } catch {
            setError(error)
        }
    }

    func refreshRecycleBin() async {
        do {
            let snapshot = try await conversationMaintenance.recycleBinSnapshot()
            recycleBinSnapshot = snapshot
            selectedRecycleBinTokens = selectedRecycleBinTokens.filter { token in
                snapshot.entries.contains { $0.token == token }
            }
        } catch {
            setError(error)
        }
    }

    func toggleRecycleBinSelection(_ entry: CodexRecycleBinEntry) {
        if selectedRecycleBinTokens.contains(entry.token) {
            selectedRecycleBinTokens.remove(entry.token)
        } else {
            selectedRecycleBinTokens.insert(entry.token)
        }
    }

    func toggleAllRecycleBinEntries() {
        if allRecycleBinEntriesSelected {
            selectedRecycleBinTokens.removeAll()
        } else {
            selectedRecycleBinTokens = Set(recycleBinSnapshot.entries.map(\.token))
        }
    }

    func restoreSelectedRecycleBinEntries() async {
        let tokens = selectedRecoverableRecycleBinTokens
        guard !tokens.isEmpty else { return }
        isRecycleBinActionRunning = true
        defer { isRecycleBinActionRunning = false }
        do {
            let result = try await conversationMaintenance.restoreRecycleBinEntries(tokens: tokens)
            recycleBinResult = result
            maintenanceMessage = result.message
            selectedRecycleBinTokens.subtract(result.succeededTokens)
            await refreshRecycleBin()
        } catch {
            setError(error)
        }
    }

    func deleteSelectedRecycleBinEntries() async {
        let tokens = Array(selectedRecycleBinTokens)
        guard !tokens.isEmpty else { return }
        isRecycleBinActionRunning = true
        defer { isRecycleBinActionRunning = false }
        do {
            let result = try await conversationMaintenance.deleteRecycleBinEntries(tokens: tokens)
            recycleBinResult = result
            maintenanceMessage = result.message
            selectedRecycleBinTokens.subtract(result.succeededTokens)
            await refreshRecycleBin()
        } catch {
            setError(error)
        }
    }

    private func saveDraftThrowing(rawMode: Bool, keyStorageMode: APIProviderKeyStorageMode) async throws -> CLIAPIProvider {
        guard let draftProviderID,
              let existing = provider(cli: draftCLI, id: draftProviderID) else {
            throw ConfigurationProviderStoreError.providerNotFound
        }

        let saved: CLIAPIProvider
        var replacedSecrets: [APIProviderSecret] = []
        if existing.origin.kind == .universal, let universalID = existing.origin.universalID {
            guard let universalIndex = library.universalProviders.firstIndex(where: { $0.id == universalID }) else {
                throw ConfigurationProviderStoreError.providerNotFound
            }
            replacedSecrets.append(library.universalProviders[universalIndex].apiKey)
            let updatedUniversal = try store.universalBySavingDraft(
                existing: library.universalProviders[universalIndex],
                editedCLI: draftCLI,
                name: draftName,
                baseURL: draftBaseURL,
                apiKey: draftAPIKey,
                model: draftModel,
                keyStorageMode: keyStorageMode
            )
            library.universalProviders[universalIndex] = updatedUniversal
            let removedChildren = library.cliProviders.filter { $0.origin.kind == .universal && $0.origin.universalID == universalID }
            replacedSecrets.append(contentsOf: removedChildren.map(\.apiKey))
            library.cliProviders.removeAll { $0.origin.kind == .universal && $0.origin.universalID == universalID }
            library.cliProviders.append(contentsOf: store.childProviders(for: updatedUniversal, keyStorageMode: keyStorageMode))
            let childID = ConfigurationProviderStore.universalChildID(universalID: universalID, cli: draftCLI)
            guard let child = provider(cli: draftCLI, id: childID) else {
                throw ConfigurationProviderStoreError.providerNotFound
            }
            saved = child
        } else {
            let updated = try store.providerBySavingDraft(
                existing: existing,
                name: draftName,
                category: draftCategory,
                baseURL: draftBaseURL,
                apiKey: draftAPIKey,
                model: draftModel,
                rawConfig: draftRawConfig,
                rawMode: rawMode,
                keyStorageMode: keyStorageMode
            )
            replacedSecrets.append(existing.apiKey)
            replaceCLIProvider(updated)
            saved = updated
        }

        try await store.saveLibrary(library)
        store.deleteStoredSecrets(replacedSecrets, retainedIn: library)
        draftIsDirty = false
        return saved
    }

    private func normalizeSelection(keyStorageMode: APIProviderKeyStorageMode) {
        if selectedCLI == .claude && selectedClaudeMode == .official {
            selectedProviderID = nil
            clearDraft()
            return
        }

        let available = providers(for: selectedCLI)
        if let selectedProviderID,
           available.contains(where: { $0.id == selectedProviderID }) {
            if let provider = provider(cli: selectedCLI, id: selectedProviderID) {
                openDraft(provider, keyStorageMode: keyStorageMode)
            }
            return
        }

        let preferredID = library.activeProviderIDs[selectedCLI] ?? available.first?.id
        selectedProviderID = preferredID
        if let preferredID, let provider = provider(cli: selectedCLI, id: preferredID) {
            openDraft(provider, keyStorageMode: keyStorageMode)
        } else {
            clearDraft()
        }
    }

    private func openDraft(_ provider: CLIAPIProvider, keyStorageMode _: APIProviderKeyStorageMode) {
        draftDetailGeneration += 1
        let inlineAPIKey: String
        switch provider.apiKey {
        case .inline(let value):
            inlineAPIKey = value
        case .none, .keychain:
            inlineAPIKey = ""
        }

        isOpeningDraft = true
        draftProviderID = provider.id
        draftCLI = provider.cli
        draftOrigin = provider.origin
        draftName = provider.name
        draftCategory = provider.category
        draftBaseURL = provider.baseURL
        draftAPIKey = inlineAPIKey
        draftModel = provider.model
        draftRawConfig = provider.rawConfig
        draftIsDirty = false
        isDraftDetailLoading = provider.apiKey.keychainAccount != nil || provider.rawConfig.isEmpty
        isOpeningDraft = false
    }

    private func clearDraft() {
        draftDetailGeneration += 1
        isOpeningDraft = true
        draftProviderID = nil
        draftOrigin = nil
        draftName = ""
        draftCategory = .custom
        draftBaseURL = ""
        draftAPIKey = ""
        draftModel = ""
        draftRawConfig = ""
        draftIsDirty = false
        isDraftDetailLoading = false
        isOpeningDraft = false
    }

    private func loadDraftDetails(for provider: CLIAPIProvider) async {
        guard draftProviderID == provider.id,
              draftCLI == provider.cli else {
            return
        }
        guard !draftIsDirty else {
            isDraftDetailLoading = false
            return
        }

        let generation = draftDetailGeneration
        let initialAPIKey = draftAPIKey
        let initialRawConfig = draftRawConfig
        isDraftDetailLoading = true

        let store = store
        let details = await Task.detached(priority: .utility) {
            let apiKey = store.resolvedAPIKey(for: provider.apiKey)
            return (
                apiKey: apiKey,
                rawConfig: store.renderRawConfig(for: provider, resolvedAPIKey: apiKey)
            )
        }.value

        guard draftDetailGeneration == generation,
              draftProviderID == provider.id,
              draftCLI == provider.cli else {
            return
        }

        let wasDirty = draftIsDirty
        isOpeningDraft = true
        if draftAPIKey == initialAPIKey {
            draftAPIKey = details.apiKey
        }
        if draftRawConfig == initialRawConfig {
            draftRawConfig = details.rawConfig
        }
        isDraftDetailLoading = false
        isOpeningDraft = false
        draftIsDirty = wasDirty
    }

    private func provider(cli: APIProviderCLI, id: String) -> CLIAPIProvider? {
        library.cliProviders.first { $0.cli == cli && $0.id == id }
    }

    private func replaceCLIProvider(_ provider: CLIAPIProvider) {
        if let index = library.cliProviders.firstIndex(where: { $0.cli == provider.cli && $0.id == provider.id }) {
            library.cliProviders[index] = provider
        } else {
            library.cliProviders.append(provider)
        }
    }

    private func markDraftDirty<T: Equatable>(_ oldValue: T, _ newValue: T) {
        guard !isOpeningDraft, oldValue != newValue else { return }
        draftIsDirty = true
    }

    private func setError(_ error: Error) {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            lastError = description
        } else {
            lastError = error.localizedDescription
        }
    }

    private static func sortRank(_ provider: CLIAPIProvider) -> Int {
        switch provider.origin.kind {
        case .official: 0
        case .importedDefault: 1
        case .universal: 2
        case .appSpecific: 3
        }
    }
}
