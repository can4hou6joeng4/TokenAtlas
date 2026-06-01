import AppKit
import SwiftUI

struct ConfigurationsView: View {
    @Environment(AppEnvironment.self) private var env

    private let workspaceMaxWidth: CGFloat = 1100
    private let providerColumnWidth: CGFloat = 330
    private let columnSpacing: CGFloat = 14
    private let railMinimumHeight: CGFloat = 144
    private let editorModeContentHeight: CGFloat = 176

    @State private var editorMode: APIProviderEditorMode = .fields
    @State private var cursorLine = 1
    @State private var cursorColumn = 1
    @State private var showEnvironmentCleanupConfirmation = false
    @State private var showProviderSyncConfirmation = false
    @State private var showRecycleDeleteConfirmation = false

    var body: some View {
        @Bindable var vm = env.apiProviders
        let environmentVM = env.cliEnvironment

        CenteredPaneContainer(maxWidth: workspaceMaxWidth, topPadding: 36) {
            VStack(alignment: .leading, spacing: 18) {
                header(vm: vm)
                configurationWorkspace(vm: vm)

                CLIEnvironmentSection(
                    vm: environmentVM,
                    requestDelete: { showEnvironmentCleanupConfirmation = true },
                    copyText: copyToClipboard,
                    openURL: openExternalURL
                )
            }
        }
        .task {
            NSApp.activate(ignoringOtherApps: true)
            await environmentVM.loadIfNeeded()
            await vm.loadIfNeeded(keyStorageMode: env.preferences.apiProviderKeyStorageMode)
            await vm.loadConversationMaintenanceIfNeeded()
            NSApp.activate(ignoringOtherApps: true)
        }
        .onChange(of: env.preferences.apiProviderKeyStorageMode) { _, newMode in
            Task { await vm.reload(keyStorageMode: newMode) }
        }
        .alert("Configuration Error", isPresented: errorBinding) {
            Button("OK") { vm.clearError() }
        } message: {
            Text(vm.lastError ?? "")
        }
        .alert("Delete Environment Variables?", isPresented: $showEnvironmentCleanupConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await env.cliEnvironment.deleteSelectedConflicts() }
            }
        } message: {
            Text("Selected shell config lines will be backed up first, then removed. Process environment variables and read-only files are skipped.")
        }
        .alert("同步历史会话归属？", isPresented: $showProviderSyncConfirmation) {
            Button("取消", role: .cancel) {}
            Button("同步", role: .destructive) {
                Task { await env.apiProviders.runProviderSync() }
            }
        } message: {
            let snapshot = env.apiProviders.providerSyncSnapshot
            Text("将历史对话归属同步为“\(env.apiProviders.selectedProviderSyncTarget)”，预计影响 \(snapshot?.totalPendingUpdates ?? 0) 项。")
        }
        .alert("永久删除回收站记录？", isPresented: $showRecycleDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("永久删除", role: .destructive) {
                Task { await env.apiProviders.deleteSelectedRecycleBinEntries() }
            }
        } message: {
            Text("将永久删除选中的 \(env.apiProviders.selectedRecycleBinTokens.count) 条恢复备份。删除后不能恢复。")
        }
    }

    private func header(vm: APIProviderSwitcherViewModel) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("API Provider Switcher")
                    .font(.sora(28, weight: .semibold))
                HStack(spacing: 8) {
                    Text(vm.selectedCLI.displayName)
                    Text("·")
                    Text(env.preferences.apiProviderKeyStorageMode.displayName)
                }
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
            }
            Spacer(minLength: 12)
            if vm.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func cliSelectorStrip(vm: APIProviderSwitcherViewModel) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("工具类型")
                .font(.sora(11, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 58, alignment: .leading)

            HStack(spacing: 6) {
                ForEach(APIProviderCLI.allCases) { cli in
                    APICLISelectorButton(
                        cli: cli,
                        isSelected: vm.selectedCLI == cli
                    ) {
                        editorMode = .fields
                        vm.selectCLI(cli, keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                    }
                }
            }

            Spacer(minLength: 8)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke.opacity(0.7), lineWidth: 1))
    }

    @ViewBuilder
    private func configurationWorkspace(vm: APIProviderSwitcherViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            cliSelectorStrip(vm: vm)

            if vm.selectedCLI == .codex {
                codexWorkspace(vm: vm)
            } else {
                claudeWorkspace(vm: vm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func codexWorkspace(vm: APIProviderSwitcherViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            codexChannelPanel(vm: vm)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
    }

    private func claudeWorkspace(vm: APIProviderSwitcherViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            claudeModePanel(vm: vm)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
    }

    private func claudeModePanel(vm: APIProviderSwitcherViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            claudeModePicker(vm: vm)
            if vm.selectedClaudeMode == .customSettings {
                claudeSettingsCandidatesPanel(vm: vm)
                claudeProfileStrip(vm: vm)
                if vm.draftProviderID == nil {
                    claudeEmptyEditorPanel(vm: vm)
                } else {
                    editorPanel(vm: vm)
                }
            } else {
                claudeOfficialPanel(vm: vm)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: railMinimumHeight, alignment: .topLeading)
        .appSurface(.compactCard(radius: 8, cornerStyle: .circular, maxWidth: nil))
        .task {
            await vm.loadClaudeSettingsCandidates()
        }
    }

    private func claudeModePicker(vm: APIProviderSwitcherViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(Color.stxMuted)
                Text("选择 Claude 配置方式")
                    .font(.sora(14, weight: .semibold))
                Spacer(minLength: 8)
                Text("claude --settings <file>")
                    .font(.sora(10).monospaced())
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                ForEach(ClaudeProviderMode.allCases) { mode in
                    ClaudeModeCard(
                        mode: mode,
                        isSelected: vm.selectedClaudeMode == mode,
                        isDisabled: vm.isWorking
                    ) {
                        editorMode = .fields
                        vm.selectClaudeMode(mode, keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    private func claudeOfficialPanel(vm: APIProviderSwitcherViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(Color.stxMuted)
                Text("官方配置")
                    .font(.sora(14, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("使用 Claude Code 默认 settings.json")
                    .font(.sora(13, weight: .semibold))
                Text("保持 Claude 官方配置路径，不挂载中转配置列表和编辑器。需要维护 settings.<name>.json 时再切换到自定义 settings。")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer(minLength: 8)
                Button {
                    vm.selectClaudeMode(.customSettings, keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                } label: {
                    Label("管理自定义 settings", systemImage: "slider.horizontal.3")
                }
                .controlSize(.small)
                .disabled(vm.isWorking)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    private func claudeSettingsCandidatesPanel(vm: APIProviderSwitcherViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "doc.badge.gearshape")
                    .foregroundStyle(Color.stxMuted)
                Text("可导入 settings 文件")
                    .font(.sora(14, weight: .semibold))
                Spacer(minLength: 8)
                if vm.isLoadingClaudeSettingsCandidates {
                    ProgressView().controlSize(.small)
                }
            }

            if vm.claudeSettingsCandidates.isEmpty {
                Text("未发现 settings.<name>.json。")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(vm.claudeSettingsCandidates) { candidate in
                        ClaudeSettingsCandidateRow(candidate: candidate, isWorking: vm.isWorking) {
                            Task {
                                await vm.importClaudeSettingsCandidate(
                                    candidate,
                                    keyStorageMode: env.preferences.apiProviderKeyStorageMode
                                )
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    private func claudeProfileStrip(vm: APIProviderSwitcherViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("配置档")
                    .font(.sora(15, weight: .semibold))
                Spacer(minLength: 8)
                Button {
                    Task {
                        await vm.importCurrent(keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                        reactivateTokenAtlas()
                    }
                } label: {
                    Label("导入默认", systemImage: "square.and.arrow.down")
                }
                .controlSize(.small)
                .disabled(vm.isWorking)
                Button {
                    Task {
                        await vm.addProvider(keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                        reactivateTokenAtlas()
                    }
                } label: {
                    Label("新增", systemImage: "plus")
                }
                .controlSize(.small)
                .disabled(vm.isWorking)
            }

            if vm.claudeProfiles.isEmpty {
                Text("暂无 Claude 自定义配置档。可从 settings.<name>.json 导入，或手动新增。")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.claudeProfiles) { provider in
                            CodexProfileChip(
                                provider: provider,
                                isSelected: vm.selectedProviderID == provider.id,
                                isActive: vm.isActive(provider)
                            ) {
                                editorMode = .fields
                                vm.selectProvider(provider, keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                    .padding(.trailing, 2)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    private func claudeEmptyEditorPanel(vm: APIProviderSwitcherViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("请选择或导入 Claude 配置档")
                .font(.sora(13, weight: .semibold))
            Text("选择配置档后才会加载 fields/raw 编辑器，避免进入 Claude 标签时进行重型渲染。")
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task {
                    await vm.addProvider(keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                    reactivateTokenAtlas()
                }
            } label: {
                Label("新增配置", systemImage: "plus")
            }
            .controlSize(.small)
            .disabled(vm.isWorking)
        }
        .padding(12)
        .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func providersColumn(vm: APIProviderSwitcherViewModel) -> some View {
        if vm.selectedCLI == .codex {
            codexProfilesColumn(vm: vm)
        } else {
            legacyProvidersColumn(vm: vm)
        }
    }

    private func legacyProvidersColumn(vm: APIProviderSwitcherViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Providers")
                    .font(.sora(15, weight: .semibold))
                Spacer(minLength: 8)
                Button {
                    Task {
                        await vm.importCurrent(keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                        reactivateTokenAtlas()
                    }
                } label: {
                    Label("Import Current", systemImage: "square.and.arrow.down")
                }
                .controlSize(.small)
                .disabled(vm.isWorking)
                Menu {
                    Button {
                        Task {
                            await vm.addProvider(keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                            reactivateTokenAtlas()
                        }
                    } label: {
                        Label("Provider", systemImage: "plus")
                    }
                    Button {
                        Task { await vm.addUniversalProvider(keyStorageMode: env.preferences.apiProviderKeyStorageMode) }
                    } label: {
                        Label("Universal Provider", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.button)
                .controlSize(.small)
                .disabled(vm.isWorking)
                .help("New provider")
            }

            AppScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(spacing: 0) {
                        let providers = vm.providers(for: vm.selectedCLI)
                        if providers.isEmpty {
                            Text("No providers")
                                .font(.sora(12))
                                .foregroundStyle(Color.stxMuted)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(providers) { provider in
                                APIProviderListRow(
                                    provider: provider,
                                    isSelected: vm.selectedProviderID == provider.id,
                                    isActive: vm.isActive(provider),
                                    localizedBadges: vm.selectedCLI == .codex
                                ) {
                                    editorMode = .fields
                                    vm.selectProvider(provider, keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                                }
                                if provider.id != providers.last?.id {
                                    StxRule().padding(.leading, 12)
                                }
                            }
                        }
                    }
                    .appSurface(.compactCard(radius: 8, cornerStyle: .circular))

                    if let result = vm.latestApplyResult {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last backup")
                                .font(.sora(10, weight: .semibold))
                                .foregroundStyle(Color.stxMuted)
                            Text(result.backupDirectory.path)
                                .font(.sora(10).monospaced())
                                .foregroundStyle(Color.stxMuted)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appSurface(.compactCard(radius: 8, fillOpacity: 0.55, cornerStyle: .circular), padding: nil)
                    }
                }
                .padding(.trailing, 2)
            }
        }
        .frame(minWidth: providerColumnWidth, maxWidth: .infinity, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func editorColumn(vm: APIProviderSwitcherViewModel) -> some View {
        editorPanel(vm: vm)
            .frame(minWidth: providerColumnWidth, maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func editorPanel(vm: APIProviderSwitcherViewModel) -> some View {
        if vm.selectedCLI == .codex {
            codexChannelPanel(vm: vm)
        } else if vm.draftProviderID == nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("No provider selected")
                    .font(.sora(16, weight: .semibold))
                Text("Create or import a provider.")
                    .font(.sora(12))
                    .foregroundStyle(Color.stxMuted)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: railMinimumHeight, alignment: .topLeading)
            .appSurface(.compactCard(radius: 8, cornerStyle: .circular, maxWidth: nil))
        } else {
            VStack(alignment: .leading, spacing: 14) {
                editorHeader(vm: vm)
                Picker("", selection: $editorMode) {
                    ForEach(APIProviderEditorMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)

                if editorMode == .fields {
                    providerFields(vm: vm)
                        .frame(height: editorModeContentHeight, alignment: .top)
                } else {
                    rawEditor(vm: vm)
                        .frame(height: editorModeContentHeight, alignment: .top)
                }

                editorActions(vm: vm)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: railMinimumHeight, alignment: .topLeading)
            .appSurface(.compactCard(radius: 8, cornerStyle: .circular, maxWidth: nil))
            .task(id: vm.draftProviderID) {
                await vm.loadSelectedDraftDetailsIfNeeded()
            }
        }
    }

    private func codexProfilesColumn(vm: APIProviderSwitcherViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("配置档")
                    .font(.sora(15, weight: .semibold))
                Spacer(minLength: 8)
                Button {
                    Task {
                        await vm.importCurrent(keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                        reactivateTokenAtlas()
                    }
                } label: {
                    Label("导入当前", systemImage: "square.and.arrow.down")
                }
                .controlSize(.small)
                .disabled(vm.isWorking)
                Button {
                    Task {
                        await vm.addCodexProfile(keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                        reactivateTokenAtlas()
                    }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 22)
                }
                .controlSize(.small)
                .disabled(vm.isWorking)
                .help("新增配置")
            }

            AppScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(spacing: 0) {
                        let profiles = vm.codexProfiles
                        if profiles.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("暂无混合中转配置")
                                    .font(.sora(12, weight: .semibold))
                                Text("新增配置后填写 Base URL 和 API Key。")
                                    .font(.sora(11))
                                    .foregroundStyle(Color.stxMuted)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(profiles) { provider in
                                APIProviderListRow(
                                    provider: provider,
                                    isSelected: vm.selectedProviderID == provider.id,
                                    isActive: vm.isActive(provider),
                                    localizedBadges: true
                                ) {
                                    vm.selectProvider(provider, keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                                }
                                if provider.id != profiles.last?.id {
                                    StxRule().padding(.leading, 12)
                                }
                            }
                        }
                    }
                    .appSurface(.compactCard(radius: 8, cornerStyle: .circular))

                    if let result = vm.latestApplyResult {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("最近备份")
                                .font(.sora(10, weight: .semibold))
                                .foregroundStyle(Color.stxMuted)
                            Text(result.backupDirectory.path)
                                .font(.sora(10).monospaced())
                                .foregroundStyle(Color.stxMuted)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appSurface(.compactCard(radius: 8, fillOpacity: 0.55, cornerStyle: .circular), padding: nil)
                    }
                }
                .padding(.trailing, 2)
            }
        }
        .frame(minWidth: providerColumnWidth, maxWidth: .infinity, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func codexProfileStrip(vm: APIProviderSwitcherViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("配置档")
                    .font(.sora(15, weight: .semibold))
                Spacer(minLength: 8)
                Button {
                    Task {
                        await vm.importCurrent(keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                        reactivateTokenAtlas()
                    }
                } label: {
                    Label("导入当前", systemImage: "square.and.arrow.down")
                }
                .controlSize(.small)
                .disabled(vm.isWorking)
                Button {
                    Task {
                        await vm.addCodexProfile(keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                        reactivateTokenAtlas()
                    }
                } label: {
                    Label("新增", systemImage: "plus")
                }
                .controlSize(.small)
                .disabled(vm.isWorking)
            }

            if vm.codexProfiles.isEmpty {
                Text("暂无混合中转配置。")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.codexProfiles) { provider in
                            CodexProfileChip(
                                provider: provider,
                                isSelected: vm.selectedProviderID == provider.id,
                                isActive: vm.isActive(provider)
                            ) {
                                vm.selectProvider(provider, keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                    .padding(.trailing, 2)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    private func codexChannelPanel(vm: APIProviderSwitcherViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            codexStatusPanel(vm: vm)
            codexChannelPicker(vm: vm)
            if vm.selectedCodexChannel == .hybridRelay {
                codexProfileStrip(vm: vm)
                CodexProfileEditorPanel(
                    vm: vm,
                    keyStorageMode: env.preferences.apiProviderKeyStorageMode,
                    reactivateTokenAtlas: reactivateTokenAtlas
                )
            } else {
                codexOfficialPanel(vm: vm)
            }
            CodexConversationMaintenancePanel(
                vm: vm,
                showProviderSyncConfirmation: $showProviderSyncConfirmation,
                showRecycleDeleteConfirmation: $showRecycleDeleteConfirmation
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: railMinimumHeight, alignment: .topLeading)
        .appSurface(.compactCard(radius: 8, cornerStyle: .circular, maxWidth: nil))
        .task {
            await vm.refreshCodexChannelStatus()
        }
    }

    private func codexStatusPanel(vm: APIProviderSwitcherViewModel) -> some View {
        let status = vm.codexChannelStatus
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(status.configured || status.channel == .official ? Color.stxAccent : .orange)
                Text("当前状态")
                    .font(.sora(14, weight: .semibold))
                Spacer(minLength: 8)
                Text(status.configPath)
                    .font(.sora(10).monospaced())
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(status.configPath)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], alignment: .leading, spacing: 10) {
                CodexStatusMetric(title: "官方登录", value: status.authenticated ? "已检测" : "未检测")
                CodexStatusMetric(title: "当前通道", value: status.channel.displayName)
                CodexStatusMetric(title: "配置档", value: status.activeProfileName)
                CodexStatusMetric(title: "已配置", value: status.configured || status.channel == .official ? "是" : "否")
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(status.authenticated ? Color(red: 0.0, green: 0.65, blue: 0.38) : .orange)
                    .frame(width: 7, height: 7)
                Text("登录账号")
                    .foregroundStyle(Color.stxMuted)
                Text(status.accountLabel ?? "未读取到账号信息")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
            }
            .font(.sora(11))
        }
        .padding(12)
        .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    private func codexChannelPicker(vm: APIProviderSwitcherViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(Color.stxMuted)
                Text("选择通道")
                    .font(.sora(14, weight: .semibold))
                Spacer(minLength: 8)
                Text(vm.codexChannelStatus.authPath)
                    .font(.sora(10).monospaced())
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(vm.codexChannelStatus.authPath)
            }

            HStack(spacing: 10) {
                ForEach(CodexModelChannel.allCases) { channel in
                    CodexChannelCard(
                        channel: channel,
                        isSelected: vm.selectedCodexChannel == channel,
                        isDisabled: vm.isWorking
                    ) {
                        vm.selectCodexChannel(channel, keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    private func codexOfficialPanel(vm: APIProviderSwitcherViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(Color.stxMuted)
                Text("官方通道")
                    .font(.sora(14, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("使用 Codex/ChatGPT 官方登录")
                    .font(.sora(13, weight: .semibold))
                Text(CodexModelChannel.official.description)
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            }
            HStack {
                Spacer(minLength: 8)
                Button {
                    Task {
                        await vm.applyOfficialCodexChannel(keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                        reactivateTokenAtlas()
                    }
                } label: {
                    Label("保存官方通道", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(vm.isWorking)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    private func editorHeader(vm: APIProviderSwitcherViewModel) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(vm.draftCLI.assetName)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(Color.stxAccent)
            VStack(alignment: .leading, spacing: 7) {
                Text(vm.draftName.isEmpty ? "Provider" : vm.draftName)
                    .font(.sora(18, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    APIProviderBadge(title: vm.draftOrigin?.displayName ?? "Provider")
                    APIProviderBadge(title: vm.draftCategory.displayName)
                    if let provider = vm.selectedProvider, vm.isActive(provider) {
                        APIProviderBadge(title: "Active", tint: Color.stxAccent)
                    }
                    if vm.draftIsDirty {
                        APIProviderBadge(title: "Unsaved", tint: .orange)
                    }
                    if vm.isDraftDetailLoading {
                        APIProviderBadge(title: "Loading", tint: Color.stxAccent)
                    }
                }
            }
            Spacer(minLength: 12)
        }
    }

    private func providerFields(vm: APIProviderSwitcherViewModel) -> some View {
        @Bindable var bindableVM = vm
        let isOfficial = bindableVM.draftOrigin?.kind == .official
        let isUniversal = bindableVM.draftOrigin?.kind == .universal

        return VStack(alignment: .leading, spacing: 12) {
            APIProviderFieldRow(title: "Name") {
                TextField("Provider name", text: $bindableVM.draftName)
                    .textFieldStyle(.roundedBorder)
            }
            APIProviderFieldRow(title: "Category") {
                Picker("", selection: $bindableVM.draftCategory) {
                    ForEach(APIProviderCategory.allCases) { category in
                        Text(category.displayName).tag(category)
                    }
                }
                .labelsHidden()
                .disabled(isUniversal)
            }
            APIProviderFieldRow(title: "Base URL") {
                TextField("https://api.example.com", text: $bindableVM.draftBaseURL)
                    .textFieldStyle(.roundedBorder)
            }
            APIProviderFieldRow(title: "API Key") {
                SecureField("API key", text: $bindableVM.draftAPIKey)
                    .textFieldStyle(.roundedBorder)
            }
            APIProviderFieldRow(title: "Model") {
                TextField(bindableVM.draftCLI == .claude ? "claude-compatible model" : "gpt-compatible model", text: $bindableVM.draftModel)
                    .textFieldStyle(.roundedBorder)
            }
        }
            .disabled(isOfficial || bindableVM.isWorking)
    }

    private func rawEditor(vm: APIProviderSwitcherViewModel) -> some View {
        @Bindable var bindableVM = vm
        let isEditable = bindableVM.canSaveSelectedProvider && !bindableVM.isWorking

        return VStack(alignment: .leading, spacing: 8) {
            ConfigurationTextEditor(
                text: $bindableVM.draftRawConfig,
                fileKind: bindableVM.draftCLI == .claude ? .json : .toml,
                isEditable: isEditable
            ) { line, column in
                cursorLine = line
                cursorColumn = column
            }
            .frame(maxHeight: .infinity)
            .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke, lineWidth: 1))

            HStack(spacing: 8) {
                Text(bindableVM.draftCLI == .claude ? "settings.json" : "config.toml")
                Text("·")
                Text("\(cursorLine):\(cursorColumn)")
                Spacer(minLength: 8)
            }
            .font(.sora(10).monospacedDigit())
            .foregroundStyle(Color.stxMuted)
        }
    }

    private func editorActions(vm: APIProviderSwitcherViewModel) -> some View {
        ViewThatFits(in: .horizontal) {
            editorActionButtons(vm: vm, showLabels: true)
            editorActionButtons(vm: vm, showLabels: false)
        }
        .controlSize(.small)
    }

    private func editorActionButtons(vm: APIProviderSwitcherViewModel, showLabels: Bool) -> some View {
        HStack(spacing: 10) {
            Button(role: .destructive) {
                Task {
                    await vm.deleteSelectedProvider(keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                    reactivateTokenAtlas()
                }
            } label: {
                actionLabel("Delete", systemImage: "trash", showLabels: showLabels)
            }
            .fixedSize(horizontal: showLabels, vertical: false)
            .disabled(!vm.canDeleteSelectedProvider || vm.isWorking)
            .help("Delete")

            Spacer(minLength: 12)

            Button {
                vm.resetDraft(keyStorageMode: env.preferences.apiProviderKeyStorageMode)
            } label: {
                actionLabel("Revert", systemImage: "arrow.uturn.backward", showLabels: showLabels)
            }
            .fixedSize(horizontal: showLabels, vertical: false)
            .disabled(!vm.draftIsDirty || vm.isWorking)
            .help("Revert")

            Button {
                Task {
                    await vm.saveDraft(rawMode: editorMode == .raw, keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                    reactivateTokenAtlas()
                }
            } label: {
                actionLabel("Save Provider", systemImage: "square.and.arrow.down", showLabels: showLabels)
            }
            .fixedSize(horizontal: showLabels, vertical: false)
            .disabled(!vm.canSaveSelectedProvider || !vm.draftIsDirty || vm.isWorking)
            .help("Save Provider")

            Button {
                Task {
                    await vm.enableSelectedProvider(rawMode: editorMode == .raw, keyStorageMode: env.preferences.apiProviderKeyStorageMode)
                    reactivateTokenAtlas()
                }
            } label: {
                actionLabel("Enable Provider", systemImage: "bolt.fill", showLabels: showLabels)
            }
            .fixedSize(horizontal: showLabels, vertical: false)
            .buttonStyle(.borderedProminent)
            .disabled(vm.selectedProvider == nil || vm.isWorking)
            .help("Enable Provider")
        }
    }

    @ViewBuilder
    private func actionLabel(_ title: String, systemImage: String, showLabels: Bool) -> some View {
        if showLabels {
            Label(title, systemImage: systemImage)
        } else {
            Image(systemName: systemImage)
                .frame(width: 22, height: 18)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { env.apiProviders.lastError != nil },
            set: { newValue in
                if !newValue { env.apiProviders.clearError() }
            }
        )
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func openExternalURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    @MainActor
    private func reactivateTokenAtlas() {
        DockVisibilityCoordinator.shared.bringVisibleWindowsForward()
    }
}

private struct CodexProfileEditorPanel: View {
    var vm: APIProviderSwitcherViewModel
    let keyStorageMode: APIProviderKeyStorageMode
    let reactivateTokenAtlas: @MainActor () -> Void
    @State private var localName = ""
    @State private var localBaseURL = ""
    @State private var localAPIKey = ""
    @State private var pendingDraftSync: Task<Void, Never>?
    @FocusState private var focusedDraftField: DraftField?

    private enum DraftField: Hashable {
        case name
        case baseURL
        case apiKey
    }

    private var localDraftIsDirty: Bool {
        localName != vm.draftName
            || localBaseURL != vm.draftBaseURL
            || localAPIKey != vm.draftAPIKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "network")
                    .foregroundStyle(Color.stxMuted)
                Text("混合中转配置")
                    .font(.sora(14, weight: .semibold))
                Spacer(minLength: 8)
                if vm.draftIsDirty || localDraftIsDirty {
                    APIProviderBadge(title: "未保存", tint: .orange)
                }
            }

            if vm.draftProviderID == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("请选择或新增配置档")
                        .font(.sora(13, weight: .semibold))
                    Text("混合中转需要配置名称、Base URL 和 API Key。")
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                    Button {
                        Task { await vm.addCodexProfile(keyStorageMode: keyStorageMode) }
                    } label: {
                        Label("新增配置", systemImage: "plus")
                    }
                    .controlSize(.small)
                    .disabled(vm.isWorking)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    APIProviderFieldRow(title: "配置名称") {
                        TextField("默认中转", text: $localName)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedDraftField, equals: .name)
                            .onSubmit { flushLocalDraftToViewModel() }
                    }
                    APIProviderFieldRow(title: "Base URL") {
                        TextField("https://example.com/v1", text: $localBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedDraftField, equals: .baseURL)
                            .onSubmit { flushLocalDraftToViewModel() }
                    }
                    APIProviderFieldRow(title: "API Key") {
                        SecureField("sk-...", text: $localAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedDraftField, equals: .apiKey)
                            .onSubmit { flushLocalDraftToViewModel() }
                    }
                    Text("应用混合中转时，TokenAtlas 会把该 Key 写入 Codex config.toml 的 experimental_bearer_token，供 Codex 运行时读取。")
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Button(role: .destructive) {
                            Task {
                                await vm.deleteSelectedCodexProfile(keyStorageMode: keyStorageMode)
                                reactivateTokenAtlas()
                            }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        .disabled(vm.codexProfiles.count <= 1 || vm.isWorking || vm.selectedCodexProfile?.isSystemProvider != false)

                        Spacer(minLength: 12)

                        Button {
                            cancelPendingDraftSync()
                            vm.resetDraft(keyStorageMode: keyStorageMode)
                            syncLocalDraftFromViewModel()
                        } label: {
                            Label("还原", systemImage: "arrow.uturn.backward")
                        }
                        .disabled((!vm.draftIsDirty && !localDraftIsDirty) || vm.isWorking)

                        Button {
                            flushLocalDraftToViewModel()
                            Task {
                                await vm.saveAndApplyCodexProfile(keyStorageMode: keyStorageMode)
                                syncLocalDraftFromViewModel()
                                reactivateTokenAtlas()
                            }
                        } label: {
                            Label("保存并应用", systemImage: "bolt.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            vm.isWorking
                                || localName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || localBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || localAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        .disabled(vm.isWorking)
        .onAppear { syncLocalDraftFromViewModel() }
        .onDisappear { cancelPendingDraftSync() }
        .onChange(of: vm.draftProviderID) { _, _ in syncLocalDraftFromViewModel() }
        .onChange(of: vm.draftName) { _, _ in syncLocalDraftFromViewModelIfNeeded() }
        .onChange(of: vm.draftBaseURL) { _, _ in syncLocalDraftFromViewModelIfNeeded() }
        .onChange(of: vm.draftAPIKey) { _, _ in syncLocalDraftFromViewModelIfNeeded() }
        .onChange(of: localName) { _, _ in scheduleLocalDraftSync() }
        .onChange(of: localBaseURL) { _, _ in scheduleLocalDraftSync() }
        .onChange(of: localAPIKey) { _, _ in scheduleLocalDraftSync() }
        .onChange(of: focusedDraftField) { _, field in
            if field == nil {
                flushLocalDraftToViewModel()
            }
        }
    }

    private func syncLocalDraftFromViewModelIfNeeded() {
        guard vm.draftProviderID != nil else { return }
        if !localDraftIsDirty {
            syncLocalDraftFromViewModel()
        }
    }

    private func syncLocalDraftFromViewModel() {
        cancelPendingDraftSync()
        localName = vm.draftName
        localBaseURL = vm.draftBaseURL
        localAPIKey = vm.draftAPIKey
    }

    private func scheduleLocalDraftSync() {
        guard localDraftIsDirty else { return }
        let providerID = vm.draftProviderID
        let name = localName
        let baseURL = localBaseURL
        let apiKey = localAPIKey

        pendingDraftSync?.cancel()
        pendingDraftSync = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            writeDraftToViewModel(providerID: providerID, name: name, baseURL: baseURL, apiKey: apiKey)
        }
    }

    private func flushLocalDraftToViewModel() {
        let providerID = vm.draftProviderID
        cancelPendingDraftSync()
        writeDraftToViewModel(providerID: providerID, name: localName, baseURL: localBaseURL, apiKey: localAPIKey)
    }

    private func writeDraftToViewModel(providerID: String?, name: String, baseURL: String, apiKey: String) {
        guard providerID != nil, vm.draftProviderID == providerID else { return }
        if vm.draftName != name {
            vm.draftName = name
        }
        if vm.draftBaseURL != baseURL {
            vm.draftBaseURL = baseURL
        }
        if vm.draftAPIKey != apiKey {
            vm.draftAPIKey = apiKey
        }
    }

    private func cancelPendingDraftSync() {
        pendingDraftSync?.cancel()
        pendingDraftSync = nil
    }
}

private struct CodexConversationMaintenancePanel: View {
    @Bindable var vm: APIProviderSwitcherViewModel
    @Binding var showProviderSyncConfirmation: Bool
    @Binding var showRecycleDeleteConfirmation: Bool
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                recycleBinSection
                providerSyncSection

                if let message = vm.maintenanceMessage {
                    Text(message)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 12)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundStyle(Color.stxMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text("对话维护")
                        .font(.sora(14, weight: .semibold))
                    Text(maintenanceSubtitle)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                }
                Spacer(minLength: 8)
                if isExpanded {
                    Button {
                        Task { await vm.refreshConversationMaintenance() }
                    } label: {
                        Label(vm.isMaintenanceLoading ? "刷新中" : "刷新", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .disabled(vm.isMaintenanceLoading || vm.isProviderSyncRunning || vm.isRecycleBinActionRunning)
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                Task { await vm.loadConversationMaintenanceIfNeeded() }
            }
        }
    }

    private var maintenanceSubtitle: String {
        if vm.providerSyncSnapshot == nil && vm.recycleBinSnapshot.entries.isEmpty {
            return "高级操作，展开后再检查历史归属和回收站。"
        }
        return "已加载维护状态，可预览影响或刷新。"
    }

    private var recycleBinSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .foregroundStyle(Color.stxMuted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("回收站")
                            .font(.sora(13, weight: .semibold))
                        Text("共 \(vm.recycleBinSnapshot.entries.count) 条记录，已选择 \(vm.selectedRecycleBinTokens.count) 条，可恢复 \(vm.recycleBinSnapshot.recoverableCount) 条。")
                            .font(.sora(10))
                            .foregroundStyle(Color.stxMuted)
                    }
                    Spacer(minLength: 8)
                }

                ViewThatFits(in: .horizontal) {
                    recycleBinActionButtons(showLabels: true)
                    recycleBinActionButtons(showLabels: false)
                }
            }

            if vm.recycleBinSnapshot.entries.isEmpty {
                Text("暂无已删除会话备份。")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .padding(.vertical, 4)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    CodexRecycleBinHeaderRow()
                    ForEach(vm.recycleBinSnapshot.entries) { entry in
                        CodexRecycleBinRow(
                            entry: entry,
                            isSelected: vm.selectedRecycleBinTokens.contains(entry.token),
                            toggle: { vm.toggleRecycleBinSelection(entry) }
                        )
                    }
                }
                .background(Color.black.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke, lineWidth: 1))
            }

            if let result = vm.recycleBinResult, !result.failed.isEmpty {
                Text(result.failed.map(\.message).joined(separator: "；"))
                    .font(.sora(10))
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }
        }
    }

    private var providerSyncSection: some View {
        let snapshot = vm.providerSyncSnapshot
        let providerOptions = snapshot?.availableProviders ?? [ConfigurationProviderStore.codexManagedProviderKey]

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Color.stxMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text("历史会话归属同步")
                        .font(.sora(13, weight: .semibold))
                    Text(providerSyncStatusText(snapshot))
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                }
                Spacer(minLength: 8)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    providerSyncTargetPicker(providerOptions: providerOptions)
                    Spacer(minLength: 8)
                    providerSyncActionButtons(showLabels: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    providerSyncTargetPicker(providerOptions: providerOptions)
                    providerSyncActionButtons(showLabels: true)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], alignment: .leading, spacing: 8) {
                CodexStatusMetric(title: "当前配置", value: snapshot?.currentProvider ?? "-")
                CodexStatusMetric(title: "目标归属", value: vm.selectedProviderSyncTarget)
                CodexStatusMetric(title: "原始文件", value: "\(snapshot?.rolloutFiles ?? 0)")
                CodexStatusMetric(title: "待改文件", value: "\(snapshot?.rolloutRewriteNeeded ?? 0)")
                CodexStatusMetric(title: "本地索引", value: "\(snapshot?.sqliteRows ?? 0)")
                CodexStatusMetric(title: "待改索引", value: "\(snapshot?.sqliteProviderRowsNeedingSync ?? 0)")
            }

            if let snapshot {
                DisclosureGroup("查看技术详情") {
                    VStack(alignment: .leading, spacing: 6) {
                        providerCountsLine(title: "原始文件", counts: snapshot.rolloutProviders)
                        providerCountsLine(title: "本地索引", counts: snapshot.sqliteProviders)
                        if let result = vm.providerSyncResult, let backup = result.backupDirectory {
                            Text("最近备份：\(backup.path)")
                                .textSelection(.enabled)
                        }
                    }
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
                    .padding(.top, 4)
                }
                .font(.sora(10, weight: .medium))
            }
        }
    }

    private func recycleBinActionButtons(showLabels: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                vm.toggleAllRecycleBinEntries()
            } label: {
                actionLabel(vm.allRecycleBinEntriesSelected ? "取消全选" : "全选", systemImage: "checklist", showLabels: showLabels)
            }
            .fixedSize(horizontal: showLabels, vertical: false)
            .disabled(vm.recycleBinSnapshot.entries.isEmpty || vm.isRecycleBinActionRunning)

            Button {
                Task { await vm.restoreSelectedRecycleBinEntries() }
            } label: {
                actionLabel(vm.isRecycleBinActionRunning ? "处理中" : "恢复可恢复项", systemImage: "arrow.uturn.backward", showLabels: showLabels)
            }
            .fixedSize(horizontal: showLabels, vertical: false)
            .disabled(vm.selectedRecoverableRecycleBinTokens.isEmpty || vm.isRecycleBinActionRunning)

            Button(role: .destructive) {
                showRecycleDeleteConfirmation = true
            } label: {
                actionLabel("永久删除", systemImage: "trash.fill", showLabels: showLabels)
            }
            .fixedSize(horizontal: showLabels, vertical: false)
            .disabled(vm.selectedRecycleBinTokens.isEmpty || vm.isRecycleBinActionRunning)
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func providerSyncTargetPicker(providerOptions: [String]) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("目标归属")
                .font(.sora(10, weight: .medium))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 62, alignment: .leading)
            Picker("", selection: $vm.providerSyncTarget) {
                ForEach(providerOptions, id: \.self) { provider in
                    Text(provider).tag(provider)
                }
                Text("自定义").tag("__custom")
            }
            .labelsHidden()
            .frame(width: 148)
            .onChange(of: vm.providerSyncTarget) { _, newValue in
                vm.selectProviderSyncTarget(newValue)
            }
            if vm.useCustomProviderSyncTarget {
                TextField("Provider 名称", text: $vm.customProviderSyncTarget)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 160)
            }
        }
    }

    private func providerSyncActionButtons(showLabels: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { await vm.previewProviderSync() }
            } label: {
                actionLabel(vm.isProviderSyncRunning ? "检查中" : "预览影响", systemImage: "eye", showLabels: showLabels)
            }
            .fixedSize(horizontal: showLabels, vertical: false)
            .disabled(vm.isProviderSyncRunning)

            Button {
                showProviderSyncConfirmation = true
            } label: {
                actionLabel("同步", systemImage: "checkmark.arrow.trianglehead.2.clockwise.rotate.90", showLabels: showLabels)
            }
            .fixedSize(horizontal: showLabels, vertical: false)
            .buttonStyle(.borderedProminent)
            .disabled(!vm.canRunProviderSync)
        }
        .controlSize(.small)
    }

    private func providerSyncStatusText(_ snapshot: CodexProviderSyncSnapshot?) -> String {
        guard let snapshot else { return "选择目标归属后预览影响，再决定是否同步。" }
        if snapshot.totalPendingUpdates > 0 {
            return "预计更新 \(snapshot.rolloutRewriteNeeded) 个原始会话文件、\(snapshot.sqliteProviderRowsNeedingSync) 条本地索引记录。"
        }
        return "\(snapshot.rolloutFiles) 个原始会话文件、\(snapshot.sqliteRows) 条本地索引记录已对齐。"
    }

    private func providerCountsLine(title: String, counts: [CodexProviderCount]) -> some View {
        let text = counts.isEmpty
            ? "\(title)：无"
            : "\(title)：\(counts.map { "\($0.provider) \($0.count)" }.joined(separator: " · "))"
        return Text(text)
    }

    @ViewBuilder
    private func actionLabel(_ title: String, systemImage: String, showLabels: Bool) -> some View {
        if showLabels {
            Label(title, systemImage: systemImage)
        } else {
            Image(systemName: systemImage)
                .frame(width: 22, height: 18)
        }
    }
}

private enum APIProviderEditorMode: String, CaseIterable, Identifiable {
    case fields
    case raw

    var id: String { rawValue }
    var title: String {
        switch self {
        case .fields: "Fields"
        case .raw: "Raw"
        }
    }
}

private struct APIProviderListRow: View {
    let provider: CLIAPIProvider
    let isSelected: Bool
    let isActive: Bool
    var localizedBadges = false
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Image(provider.cli.assetName)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                    Text(provider.name)
                        .font(.sora(12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if isActive {
                        Circle()
                            .fill(Color.stxAccent)
                            .frame(width: 7, height: 7)
                    }
                }

                HStack(spacing: 6) {
                    APIProviderBadge(title: localizedBadges ? localizedOriginName(provider.origin) : provider.origin.displayName)
                    if provider.category != .official && provider.category != .imported {
                        APIProviderBadge(title: localizedBadges ? localizedCategoryName(provider.category) : provider.category.displayName)
                    }
                    Spacer(minLength: 6)
                }

                HStack(spacing: 6) {
                    Text(provider.baseURL.isEmpty ? (localizedBadges ? "官方端点" : "Official endpoint") : provider.baseURL)
                        .lineLimit(1)
                    if !provider.model.isEmpty {
                        Text("·")
                        Text(provider.model).lineLimit(1)
                    }
                }
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7).fill(Color.stxAccent.opacity(0.10))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func localizedOriginName(_ origin: APIProviderOrigin) -> String {
        switch origin.kind {
        case .official: "官方"
        case .importedDefault: "导入"
        case .appSpecific: "配置档"
        case .universal: "通用"
        }
    }

    private func localizedCategoryName(_ category: APIProviderCategory) -> String {
        switch category {
        case .official: "官方"
        case .imported: "导入"
        case .aggregator: "聚合"
        case .thirdParty: "第三方"
        case .custom: "自定义"
        case .universal: "通用"
        }
    }
}

private struct APICLISelectorButton: View {
    let cli: APIProviderCLI
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 7) {
                Image(cli.assetName)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)

                Text(cli.shortName)
                    .font(.sora(11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.stxMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.stxAccent.opacity(0.10) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.stxAccent.opacity(0.38) : Color.clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(cli.displayName)
        .accessibilityLabel(cli.displayName)
    }
}

private struct ClaudeModeCard: View {
    let mode: ClaudeProviderMode
    let isSelected: Bool
    let isDisabled: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: mode == .official ? "checkmark.seal" : "doc.badge.gearshape")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                    .frame(width: 28, height: 28)
                    .background((isSelected ? Color.stxAccent : Color.stxMuted).opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                Text(mode.displayName)
                    .font(.sora(13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(mode.description)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.stxAccent.opacity(0.10) : Color.black.opacity(0.025))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.stxAccent.opacity(0.55) : Color.stxStroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct ClaudeSettingsCandidateRow: View {
    let candidate: ClaudeSettingsCandidate
    let isWorking: Bool
    let importCandidate: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(Color.stxMuted)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(candidate.title)
                        .font(.sora(12, weight: .semibold))
                        .lineLimit(1)
                    APIProviderBadge(title: candidate.url.lastPathComponent)
                }
                Text(candidate.commandPreview)
                    .font(.sora(10).monospaced())
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(candidate.commandPreview)
                HStack(spacing: 6) {
                    if !candidate.baseURL.isEmpty {
                        Text(candidate.baseURL).lineLimit(1)
                    }
                    if !candidate.model.isEmpty {
                        Text("·")
                        Text(candidate.model).lineLimit(1)
                    }
                }
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
            }

            Spacer(minLength: 10)

            Button {
                importCandidate()
            } label: {
                Label("导入", systemImage: "square.and.arrow.down")
            }
            .controlSize(.small)
            .disabled(isWorking)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke, lineWidth: 1))
    }
}

private struct CodexProfileChip: View {
    let provider: CLIAPIProvider
    let isSelected: Bool
    let isActive: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .center, spacing: 9) {
                Image(provider.cli.assetName)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)

                VStack(alignment: .leading, spacing: 5) {
                    Text(provider.name)
                        .font(.sora(11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        APIProviderBadge(title: originName)
                        if isActive {
                            APIProviderBadge(title: "当前", tint: Color.stxAccent)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(width: 178, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.stxAccent.opacity(0.10) : Color.black.opacity(0.025))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.stxAccent.opacity(0.45) : Color.stxStroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(provider.name)
    }

    private var originName: String {
        switch provider.origin.kind {
        case .official: "官方"
        case .importedDefault: "导入"
        case .appSpecific: "配置档"
        case .universal: "通用"
        }
    }
}

private struct APIProviderFieldRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.sora(11, weight: .medium))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 86, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct APIProviderBadge: View {
    let title: String
    var tint: Color = Color.stxMuted

    var body: some View {
        Text(title)
            .font(.sora(9, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.2), lineWidth: 1))
    }
}

private struct CodexStatusMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.sora(10, weight: .medium))
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .font(.sora(13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CodexChannelCard: View {
    let channel: CodexModelChannel
    let isSelected: Bool
    let isDisabled: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: channel == .official ? "checkmark.seal" : "network")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                    .frame(width: 28, height: 28)
                    .background((isSelected ? Color.stxAccent : Color.stxMuted).opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                Text(channel.displayName)
                    .font(.sora(13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(channel.description)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.stxAccent.opacity(0.10) : Color.black.opacity(0.025))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.stxAccent.opacity(0.55) : Color.stxStroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct CodexRecycleBinHeaderRow: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("")
                .frame(width: 22)
            Text("标题")
                .frame(minWidth: 110, maxWidth: .infinity, alignment: .leading)
            Text("来源")
                .frame(width: 88, alignment: .leading)
            Text("最后活跃")
                .frame(width: 72, alignment: .leading)
            Text("删除时间")
                .frame(width: 72, alignment: .leading)
            Text("状态")
                .frame(width: 74, alignment: .leading)
        }
        .font(.sora(9, weight: .semibold))
        .foregroundStyle(Color.stxMuted)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

private struct CodexRecycleBinRow: View {
    let entry: CodexRecycleBinEntry
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Color.stxAccent : Color.stxMuted)
                    .frame(width: 22)
                Text(entry.title?.isEmpty == false ? entry.title! : "未命名会话")
                    .font(.sora(10, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(minWidth: 110, maxWidth: .infinity, alignment: .leading)
                Text(projectLabel(entry.projectCWD))
                    .lineLimit(1)
                    .frame(width: 88, alignment: .leading)
                Text(shortDate(entry.lastActiveAt))
                    .lineLimit(1)
                    .frame(width: 72, alignment: .leading)
                Text(shortDate(entry.deletedAt))
                    .lineLimit(1)
                    .frame(width: 72, alignment: .leading)
                APIProviderBadge(
                    title: entry.status,
                    tint: entry.recoverable ? Color(red: 0.0, green: 0.65, blue: 0.38) : .orange
                )
                .frame(width: 74, alignment: .leading)
            }
            .font(.sora(10).monospacedDigit())
            .foregroundStyle(Color.stxMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    Rectangle().fill(Color.stxAccent.opacity(0.08))
                }
            }
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private var tooltip: String {
        [
            "标题：\(entry.title ?? "未命名会话")",
            "项目：\(entry.projectCWD ?? "未知")",
            "会话 ID：\(entry.sessionID)",
            "备份：\(entry.backupPath)",
            "类型：\(entry.schema)",
            "状态：\(entry.status)",
        ].joined(separator: "\n")
    }

    private func projectLabel(_ cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "未知" }
        return URL(fileURLWithPath: cwd).lastPathComponent.isEmpty ? cwd : URL(fileURLWithPath: cwd).lastPathComponent
    }

    private func shortDate(_ date: Date?) -> String {
        guard let date else { return "-" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}

private struct CLIEnvironmentSection: View {
    private static let cardSpacing: CGFloat = 12
    private static let minimumCardWidth: CGFloat = 280

    @Bindable var vm: CLIEnvironmentViewModel
    let requestDelete: () -> Void
    let copyText: (String) -> Void
    let openURL: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Local environment check")
                    .font(.sora(15, weight: .semibold))
                if vm.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer(minLength: 0)
            }

            if !vm.isLoaded {
                automaticCheckPrompt
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Self.minimumCardWidth), spacing: Self.cardSpacing)],
                alignment: .leading,
                spacing: Self.cardSpacing
            ) {
                ForEach(APIProviderCLI.allCases) { cli in
                    CLIEnvironmentStatusCard(
                        cli: cli,
                        status: vm.status(for: cli),
                        hasChecked: vm.isLoaded,
                        isLoading: vm.isLoading,
                        copyText: copyText,
                        openURL: openURL
                    )
                }
            }

            CLIEnvironmentConflictPanel(
                vm: vm,
                requestDelete: requestDelete,
                copyText: copyText
            )

            if let lastError = vm.lastError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(lastError)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Button("Dismiss") {
                        vm.clearError()
                    }
                    .controlSize(.small)
                }
                .font(.sora(11))
                .foregroundStyle(.orange)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.25), lineWidth: 1))
            }
        }
        .padding(.top, 2)
    }

    private var automaticCheckPrompt: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: vm.isLoading ? "hourglass" : "checkmark.shield")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(vm.isLoading ? "正在检查本地 CLI 环境" : "本地 CLI 环境将自动检查")
                    .font(.sora(13, weight: .semibold))
                Text("TokenAtlas 会在进入配置页时读取 shell 配置文件并运行 CLI 版本检查；需要 macOS 授权时会直接弹出系统窗口。")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.65, cornerStyle: .circular), padding: nil)
    }
}

private struct CLIEnvironmentStatusCard: View {
    let cli: APIProviderCLI
    let status: CLIToolStatus?
    let hasChecked: Bool
    let isLoading: Bool
    let copyText: (String) -> Void
    let openURL: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "terminal")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
                Text(cli.shortName)
                    .font(.sora(18, weight: .semibold))
                    .lineLimit(1)
                APIProviderBadge(title: CLIEnvironmentType.macOS.displayName)
                Spacer(minLength: 8)
                statusAccessory
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(detailText)
                    .font(.sora(14).monospaced())
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(status?.diagnostic ?? status?.displayValue ?? "")

                cardFooter
            }
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 144, alignment: .topLeading)
        .appSurface(.compactCard(radius: 8, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private var cardFooter: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if let status, status.isOutdated, let latestVersion = status.latestVersion {
                APIProviderBadge(title: "Latest \(latestVersion)", tint: .orange)
                    .layoutPriority(1)
            }
            Spacer(minLength: 8)
            if needsInstallActions {
                installActions
            }
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .bottomLeading)
    }

    private var installActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Button {
                    copyText(cli.installCommand)
                } label: {
                    Label("Copy Install", systemImage: "doc.on.doc")
                }
                Button {
                    openURL(cli.installURL)
                } label: {
                    Label("Install Page", systemImage: "arrow.up.right.square")
                }
            }
            HStack(spacing: 8) {
                Button {
                    copyText(cli.installCommand)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 22, height: 18)
                }
                .help("Copy Install")
                Button {
                    openURL(cli.installURL)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .frame(width: 22, height: 18)
                }
                .help("Install Page")
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var statusAccessory: some View {
        if isLoading && status == nil {
            ProgressView()
                .controlSize(.small)
        } else if !hasChecked {
            Image(systemName: "clock")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.stxMuted)
        } else if status?.isInstalled == true {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(status?.isOutdated == true ? .orange : Color(red: 0.0, green: 0.65, blue: 0.38))
        } else {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.orange)
        }
    }

    private var detailText: String {
        if isLoading && status == nil {
            return "检查中..."
        }
        if !hasChecked {
            return "尚未检查"
        }
        return status?.displayValue ?? "not installed or not executable"
    }

    private var needsInstallActions: Bool {
        guard hasChecked else { return false }
        guard !isLoading else { return false }
        guard let status else { return true }
        return !status.isInstalled || status.isOutdated
    }

}

private struct CLIEnvironmentConflictPanel: View {
    @Bindable var vm: CLIEnvironmentViewModel
    let requestDelete: () -> Void
    let copyText: (String) -> Void

    var body: some View {
        if !vm.isLoaded {
            automaticScanPanel
        } else if vm.conflicts.isEmpty {
            cleanPanel
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Environment variable conflicts")
                            .font(.sora(13, weight: .semibold))
                        Text("\(vm.conflicts.count) ANTHROPIC / OPENAI variable\(vm.conflicts.count == 1 ? "" : "s") found in your local environment.")
                            .font(.sora(11))
                            .foregroundStyle(Color.stxMuted)
                    }
                    Spacer(minLength: 8)
                    Button {
                        vm.selectAllDeletableConflicts()
                    } label: {
                        Label("Select All", systemImage: "checklist")
                    }
                    .controlSize(.small)
                    .disabled(vm.isCleaning || vm.conflicts.allSatisfy { !$0.isDeletable })

                    Button(role: .destructive) {
                        requestDelete()
                    } label: {
                        Label("Delete Selected", systemImage: "trash")
                    }
                    .controlSize(.small)
                    .disabled(vm.selectedDeletableCount == 0 || vm.isCleaning)
                }

                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(vm.conflicts) { conflict in
                        CLIEnvironmentConflictRow(
                            conflict: conflict,
                            isSelected: vm.isSelected(conflict),
                            isRevealed: vm.isRevealed(conflict),
                            toggleSelection: { vm.toggleSelection(conflict) },
                            toggleReveal: { vm.toggleReveal(conflict) },
                            copyText: copyText
                        )
                    }
                }

                if let result = vm.latestCleanupResult {
                    cleanupResult(result)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.25), lineWidth: 1))
        }
    }

    private var automaticScanPanel: some View {
        HStack(spacing: 10) {
            Image(systemName: vm.isLoading ? "hourglass" : "shield.lefthalf.filled")
                .foregroundStyle(Color.stxMuted)
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.isLoading ? "正在扫描环境变量冲突" : "环境变量冲突将自动扫描")
                    .font(.sora(13, weight: .semibold))
                Text("TokenAtlas 会检查进程和 shell 配置中的 ANTHROPIC / OPENAI 覆盖变量。")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.65, cornerStyle: .circular), padding: nil)
    }

    private var cleanPanel: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Color(red: 0.0, green: 0.65, blue: 0.38))
            VStack(alignment: .leading, spacing: 2) {
                Text("No environment conflicts")
                    .font(.sora(13, weight: .semibold))
                Text("No ANTHROPIC or OPENAI overrides were found in process or shell config files.")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.65, cornerStyle: .circular), padding: nil)
    }

    private func cleanupResult(_ result: CLIEnvironmentCleanupResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last cleanup backup")
                .font(.sora(10, weight: .semibold))
                .foregroundStyle(Color.stxMuted)
            Text(result.backupDirectory.path)
                .font(.sora(10).monospaced())
                .foregroundStyle(Color.stxMuted)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            if !result.skippedConflicts.isEmpty {
                Text("\(result.skippedConflicts.count) item\(result.skippedConflicts.count == 1 ? "" : "s") skipped")
                    .font(.sora(10))
                    .foregroundStyle(.orange)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.55, cornerStyle: .circular), padding: nil)
    }
}

private struct CLIEnvironmentConflictRow: View {
    let conflict: CLIEnvironmentConflict
    let isSelected: Bool
    let isRevealed: Bool
    let toggleSelection: () -> Void
    let toggleReveal: () -> Void
    let copyText: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: toggleSelection) {
                Image(systemName: conflict.isDeletable ? (isSelected ? "checkmark.square.fill" : "square") : "lock")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(conflict.isDeletable ? Color.stxAccent : Color.stxMuted)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(!conflict.isDeletable)
            .help(conflict.isDeletable ? "Select for deletion" : "This source cannot be edited from here")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Image(conflict.cli.assetName)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(Color.stxMuted)
                    Text(conflict.varName)
                        .font(.sora(12, weight: .semibold))
                        .lineLimit(1)
                    APIProviderBadge(title: conflict.cli.shortName)
                    Spacer(minLength: 8)
                }

                HStack(spacing: 6) {
                    Text("Value:")
                    Text(isRevealed ? conflict.varValue : conflict.maskedValue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        toggleReveal()
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .frame(width: 18, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help(isRevealed ? "Hide value" : "Reveal value")
                }
                .font(.sora(10).monospaced())
                .foregroundStyle(Color.stxMuted)

                HStack(spacing: 6) {
                    Text(conflict.sourceDescription)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button {
                        copyText(conflict.varName)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .frame(width: 18, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help("Copy variable")
                    Button {
                        copyText(conflict.sourceDescription)
                    } label: {
                        Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                            .frame(width: 18, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help("Copy source")
                }
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.75, cornerStyle: .circular), padding: nil)
    }
}

#if DEBUG
#Preview {
    ConfigurationsView()
        .environment(AppEnvironment.preview())
        .frame(width: 1180, height: 780)
}
#endif
