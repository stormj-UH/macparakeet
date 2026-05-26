import SwiftUI
import MacParakeetCore
import MacParakeetViewModels

struct LLMSettingsView: View {
    @Bindable var viewModel: LLMSettingsViewModel

    @State private var showAdvancedSetup = false
    @State private var showOptionalToken = false
    @State private var showConnectionSettings = false
    @State private var cloudProviderChoice: LLMProviderID = .anthropic

    private static let cloudProviderOrder: [LLMProviderID] = [
        .anthropic,
        .openai,
        .gemini,
        .openrouter,
    ]

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            setupStatusSection

            Divider()

            localAIAppSection

            Divider()

            apiKeySection

            Divider()

            advancedSetupSection

            if viewModel.selectedProviderID != nil {
                Divider()

                selectedConfigurationSection
            }

            Divider()

            aiFormatterSection
        }
    }

    @ViewBuilder
    private var setupStatusSection: some View {
        let status = viewModel.setupStatus
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: setupStatusIcon(for: status))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(setupStatusTint(for: status))
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(setupStatusTint(for: status).opacity(0.12))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("AI for summaries and chat")
                    .font(DesignSystem.Typography.body.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text(setupStatusCopy(for: status))
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: DesignSystem.Spacing.md)

            switch status {
            case .ready:
                SettingsStatusChip(status: .ok, label: "Ready")
            case .cannotConnect:
                SettingsStatusChip(status: .recommended, label: "Check setup")
            case .setUpNeeded:
                SettingsStatusChip(status: .info, label: "Optional")
            }
        }
    }

    private var localAIAppSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            setupSectionHeader(
                title: "Use a local AI app",
                detail: "Best privacy path. Run AI on this Mac with LM Studio or Ollama."
            )

            setupPathRow(
                icon: "desktopcomputer",
                title: "LM Studio",
                badge: "Recommended",
                detail: "Friendliest local setup. Start its local server, then MacParakeet can find loaded models.",
                providerID: .lmstudio,
                actionLabel: "Use LM Studio"
            )

            Divider()

            setupPathRow(
                icon: "terminal",
                title: "Ollama",
                badge: nil,
                detail: "Local models for users who already run Ollama or prefer a command-line install.",
                providerID: .ollama,
                actionLabel: "Use Ollama"
            )
        }
    }

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            setupSectionHeader(
                title: "Use an API key",
                detail: "Use Claude, OpenAI, Gemini, or OpenRouter. Audio stays local; transcript text is sent only when you run an AI action."
            )

            HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                Image(systemName: "key.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: 24, height: 24)

                Picker("AI service", selection: cloudProviderBinding) {
                    ForEach(Self.cloudProviderOrder, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 210)

                Spacer(minLength: DesignSystem.Spacing.md)

                if let providerID = viewModel.selectedProviderID,
                   Self.cloudProviderOrder.contains(providerID) {
                    SettingsStatusChip(status: .info, label: "Selected")
                } else {
                    Button {
                        viewModel.selectedProviderID = cloudProviderChoice
                    } label: {
                        Label("Use API key", systemImage: "key")
                    }
                    .parakeetAction(.secondary)
                }
            }
        }
    }

    private var advancedSetupSection: some View {
        DisclosureGroup(isExpanded: $showAdvancedSetup) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                setupPathRow(
                    icon: "network",
                    title: "OpenAI-compatible endpoint",
                    badge: nil,
                    detail: "Connect another API or local server that speaks the OpenAI chat completions format.",
                    providerID: .openaiCompatible,
                    actionLabel: "Use endpoint"
                )

                Divider()

                setupPathRow(
                    icon: "terminal",
                    title: "Command-line AI tool",
                    badge: nil,
                    detail: "Run Claude Code, Codex, or a custom command when MacParakeet needs AI.",
                    providerID: .localCLI,
                    actionLabel: "Use CLI"
                )
            }
            .padding(.top, DesignSystem.Spacing.sm)
        } label: {
            setupSectionHeader(
                title: "Advanced setup",
                detail: "Custom endpoints and command-line AI tools for power users."
            )
        }
    }

    @ViewBuilder
    private func setupSectionHeader(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(DesignSystem.Typography.body.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Text(detail)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func setupPathRow(
        icon: String,
        title: String,
        badge: String?,
        detail: String,
        providerID: LLMProviderID,
        actionLabel: String
    ) -> some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(setupPathTint(for: providerID))
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(title)
                        .font(DesignSystem.Typography.body)
                    if let badge {
                        Text(badge)
                            .font(DesignSystem.Typography.micro.weight(.semibold))
                            .foregroundStyle(DesignSystem.Colors.accentDark)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(DesignSystem.Colors.accent.opacity(0.12)))
                    }
                }
                Text(detail)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: DesignSystem.Spacing.md)

            if viewModel.selectedProviderID == providerID {
                SettingsStatusChip(status: .info, label: "Selected")
            } else {
                Button {
                    viewModel.selectedProviderID = providerID
                } label: {
                    Label(actionLabel, systemImage: "arrow.right")
                }
                .parakeetAction(.secondary)
            }
        }
    }

    @ViewBuilder
    private var selectedConfigurationSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Setup details")
                        .font(DesignSystem.Typography.body.weight(.semibold))
                    Text(selectedConfigurationDetail)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DesignSystem.Spacing.md)
                selectedProviderChip
            }

            if viewModel.supportsAPIKey && viewModel.selectedProviderID != .lmstudio {
                Divider()
                apiKeyRow
            }

            if viewModel.selectedProviderID == .localCLI {
                Divider()
                cliSettingsSection
            } else {
                Divider()
                modelRow

                if let localModelSetupHint {
                    localModelHintRow(localModelSetupHint)
                }

                if viewModel.selectedProviderID == .lmstudio {
                    DisclosureGroup("Optional token", isExpanded: $showOptionalToken) {
                        apiKeyRow
                            .padding(.top, DesignSystem.Spacing.sm)
                    }
                    .font(DesignSystem.Typography.caption)
                }

                Divider()
                connectionSettingsSection
            }

            Divider()

            privacyInfo

            Divider()

            selectedConfigurationActions

            if let validationMessage = viewModel.validationMessage {
                validationMessageRow(validationMessage)
            }
        }
    }

    private var localModelSetupHint: String? {
        guard viewModel.canRefreshModelList, viewModel.discoveredModelCount == 0 else { return nil }
        switch viewModel.selectedProviderID {
        case .lmstudio:
            return "Open LM Studio, load a model, start the local server, then refresh models."
        case .ollama:
            return "Start Ollama, install a model, then refresh models."
        default:
            return nil
        }
    }

    private func localModelHintRow(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Text(message)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cloudProviderBinding: Binding<LLMProviderID> {
        Binding(
            get: {
                if let providerID = viewModel.selectedProviderID,
                   Self.cloudProviderOrder.contains(providerID) {
                    return providerID
                }
                return cloudProviderChoice
            },
            set: { providerID in
                cloudProviderChoice = providerID
                if let selectedProviderID = viewModel.selectedProviderID,
                   Self.cloudProviderOrder.contains(selectedProviderID) {
                    viewModel.selectedProviderID = providerID
                }
            }
        )
    }

    @ViewBuilder
    private var selectedProviderChip: some View {
        if let providerID = viewModel.selectedProviderID {
            SettingsStatusChip(
                status: providerID.isLocal ? .ok : .info,
                label: providerID.displayName
            )
        }
    }

    private var selectedConfigurationDetail: String {
        switch viewModel.selectedProviderID {
        case .lmstudio:
            return "Use LM Studio's local server. Choose a detected model, then save and test."
        case .ollama:
            return "Use your local Ollama models. MacParakeet can refresh the installed model list."
        case .localCLI:
            return "Choose a preset command or enter a custom command for AI requests."
        case .openaiCompatible:
            return "Enter the endpoint and model for an OpenAI-compatible service."
        case .anthropic, .openai, .gemini, .openrouter:
            return "Enter your API key and choose a model. Keys are stored in Keychain."
        case nil:
            return ""
        }
    }

    private var apiKeyRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.requiresAPIKey ? "API Key" : "Optional API Key")
                    .font(DesignSystem.Typography.body)
                Text(
                    viewModel.requiresAPIKey
                        ? "Stored securely in the macOS Keychain."
                        : "Leave blank for local servers that do not require authentication."
                )
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: DesignSystem.Spacing.md)
            SecureField(viewModel.apiKeyPlaceholder, text: $viewModel.apiKeyInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
        }
    }

    private var modelRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Model")
                    .font(DesignSystem.Typography.body)
                Text(modelRowDetail)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: DesignSystem.Spacing.md)
            modelPicker
        }
    }

    private var modelRowDetail: String {
        switch viewModel.selectedProviderID {
        case .lmstudio:
            return "Pick a model loaded in LM Studio."
        case .ollama:
            return "Pick an installed Ollama model, or use a recommended default."
        default:
            return "The model to use for AI features."
        }
    }

    @ViewBuilder
    private var connectionSettingsSection: some View {
        if viewModel.selectedProviderID?.requiresCustomEndpoint == true {
            endpointRow
        } else {
            DisclosureGroup("Advanced connection settings", isExpanded: $showConnectionSettings) {
                endpointRow
                    .padding(.top, DesignSystem.Spacing.sm)
            }
            .font(DesignSystem.Typography.caption)
        }
    }

    private var endpointRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.selectedProviderID?.requiresCustomEndpoint == true ? "Endpoint" : "Base URL")
                    .font(DesignSystem.Typography.body)
                Text(
                    viewModel.selectedProviderID?.requiresCustomEndpoint == true
                        ? "OpenAI-compatible base URL, for example https://api.example.com/v1."
                        : "Override the default endpoint only if your AI app or service uses a custom address."
                )
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: DesignSystem.Spacing.md)
            TextField(viewModel.baseURLPlaceholder, text: $viewModel.baseURLOverride)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
        }
    }

    private var selectedConfigurationActions: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(alignment: .top) {
                Button {
                    viewModel.saveAndTestConfiguration()
                } label: {
                    Label("Save and Test", systemImage: "checkmark.circle")
                }
                .parakeetAction(.primaryProminent)
                .disabled(!viewModel.canSave || viewModel.connectionTestState == .testing)

                Button {
                    viewModel.testConnection()
                } label: {
                    Label("Test", systemImage: "bolt")
                }
                .parakeetAction(.secondary)
                .disabled(viewModel.connectionTestState == .testing || !viewModel.canTestConnection)

                if viewModel.canRefreshModelList {
                    Button {
                        viewModel.refreshAvailableModels()
                    } label: {
                        Label("Refresh Models", systemImage: "arrow.clockwise")
                    }
                    .parakeetAction(.secondary)
                    .disabled(viewModel.isLoadingModelList)
                }

                Spacer()
            }

            HStack(alignment: .top) {
                if viewModel.isConfigured {
                    Button(role: .destructive) {
                        viewModel.selectedProviderID = nil
                        viewModel.saveConfiguration()
                    } label: {
                        Label("Turn Off AI", systemImage: "power")
                    }
                    .parakeetAction(.destructive)
                } else {
                    Button {
                        viewModel.selectedProviderID = nil
                    } label: {
                        Label("Not Now", systemImage: "xmark")
                    }
                    .parakeetAction(.secondary)
                }

                Spacer()
            }

            HStack(spacing: DesignSystem.Spacing.sm) {
                connectionStatusIndicator
                saveStateIndicator

                Spacer()
            }
        }
    }

    private func validationMessageRow(_ message: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(DesignSystem.Colors.warningAmber)
            Text(message)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.warningAmber)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setupPathTint(for providerID: LLMProviderID) -> Color {
        viewModel.selectedProviderID == providerID ? DesignSystem.Colors.accent : DesignSystem.Colors.textSecondary
    }

    private func setupStatusIcon(for status: LLMSettingsViewModel.AISetupStatus) -> String {
        switch status {
        case .setUpNeeded:
            return "sparkles"
        case .ready:
            return "checkmark"
        case .cannotConnect:
            return "exclamationmark"
        }
    }

    private func setupStatusTint(for status: LLMSettingsViewModel.AISetupStatus) -> Color {
        switch status {
        case .setUpNeeded:
            return DesignSystem.Colors.accent
        case .ready:
            return DesignSystem.Colors.successGreen
        case .cannotConnect:
            return DesignSystem.Colors.warningAmber
        }
    }

    private func setupStatusCopy(for status: LLMSettingsViewModel.AISetupStatus) -> String {
        switch status {
        case .setUpNeeded:
            return "Recording and transcription work now. Turn on AI for summaries, chat, meeting Ask, and Transforms."
        case .ready(let displayName):
            return "Ready: using \(displayName)."
        case .cannotConnect(let displayName, let message):
            return "MacParakeet could not reach \(displayName): \(message)"
        }
    }

    @ViewBuilder
    private var modelPicker: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if viewModel.useCustomModel {
                TextField("Model ID (e.g. gpt-4o)", text: $viewModel.customModelName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            } else if viewModel.availableModels.isEmpty {
                Text(viewModel.isLoadingModelList ? "Loading models..." : "No models available")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 220, alignment: .leading)
            } else {
                Picker("Model", selection: $viewModel.modelName) {
                    ForEach(viewModel.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 180)
            }

            if viewModel.useCustomModel {
                if viewModel.canChooseModelFromList {
                    Button("Choose from list") {
                        viewModel.useCustomModel = false
                    }
                    .buttonStyle(.plain)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.secondary)
                }
            } else {
                Button("Use custom model") {
                    viewModel.useCustomModel = true
                }
                .buttonStyle(.plain)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(.secondary)
            }

            if let errorMessage = viewModel.modelListErrorMessage {
                Text(errorMessage)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.warningAmber)
                    .frame(width: 220, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var aiFormatterSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text("AI Formatter")
                                .font(DesignSystem.Typography.body.weight(.semibold))
                            Text("Final step")
                                .font(DesignSystem.Typography.micro.weight(.semibold))
                                .foregroundStyle(DesignSystem.Colors.accentDark)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(DesignSystem.Colors.accent.opacity(0.12))
                                )
                        }
                        Text("Optionally run the final transcript through your selected AI option after the usual cleanup step.")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: DesignSystem.Spacing.md)
                    AIFormatterActivationToggle(
                        isOn: $viewModel.aiFormatterEnabled,
                        isAvailable: viewModel.canToggleAIFormatter,
                        disabledReason: viewModel.aiFormatterDisabledReason
                    )
                }

                if let disabledReason = viewModel.aiFormatterDisabledReason {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        Text(disabledReason)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text("Prompt")
                            .font(DesignSystem.Typography.body)
                        Text(viewModel.aiFormatterPromptModeText)
                            .font(DesignSystem.Typography.micro.weight(.semibold))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(DesignSystem.Colors.surfaceElevated)
                            )
                    }
                    Text("Uses `{{TRANSCRIPT}}` as the transcript placeholder and runs as the last output step.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: DesignSystem.Spacing.md)
                VStack(alignment: .trailing, spacing: 6) {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $viewModel.aiFormatterPrompt)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .disabled(!viewModel.canToggleAIFormatter)
                    }
                    .frame(width: 380)
                    .frame(minHeight: 220)
                    .background(DesignSystem.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                            .strokeBorder(DesignSystem.Colors.border, lineWidth: 1)
                    )

                    Button("Reset Prompt") {
                        viewModel.resetAIFormatterPrompt()
                    }
                    .buttonStyle(.plain)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.secondary)
                    .disabled(!viewModel.canResetAIFormatterPrompt)
                }
            }
        }
    }

    @ViewBuilder
    private var cliSettingsSection: some View {
        // Template picker
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CLI Tool")
                    .font(DesignSystem.Typography.body)
                Text("Choose a preset or enter a custom command.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: DesignSystem.Spacing.md)
            Picker("Template", selection: $viewModel.selectedCLITemplate) {
                Text("Custom").tag(LocalCLITemplate?.none)
                ForEach(LocalCLITemplate.allCases, id: \.self) { template in
                    Text(template.displayName).tag(Optional(template))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 160)
        }

        Divider()

        // Command editor
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Command")
                    .font(DesignSystem.Typography.body)
                Text("Prompt is passed via stdin and environment variables. Presets run from an app-owned working directory.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: DesignSystem.Spacing.md)
            TextField("claude -p", text: $viewModel.commandTemplate)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(width: 220)
        }

        Divider()

        // Timeout
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Timeout")
                    .font(DesignSystem.Typography.body)
                Text("Maximum seconds to wait for a response.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: DesignSystem.Spacing.md)
            TextField("120", value: $viewModel.cliTimeoutSeconds, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            Text("seconds")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var privacyInfo: some View {
        let isLocal = viewModel.isLocalConfiguration
        let isCLI = viewModel.selectedProviderID == .localCLI
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: isLocal ? "lock.fill" : "arrow.up.right.circle")
                .font(.system(size: 12))
                .foregroundStyle(isLocal ? DesignSystem.Colors.successGreen : DesignSystem.Colors.warningAmber)

            Text(isLocal
                 ? "Transcript text is sent only to your local AI endpoint."
                 : isCLI
                    ? "Runs a command on this Mac. The command may contact its own service."
                    : "Transcription stays local. Transcript text is sent only when you run an AI action.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                .fill(isLocal
                      ? DesignSystem.Colors.successGreen.opacity(0.06)
                      : DesignSystem.Colors.warningAmber.opacity(0.06))
        )
    }

    @ViewBuilder
    private var saveStateIndicator: some View {
        switch viewModel.saveState {
        case .idle:
            if viewModel.hasUnsavedChanges {
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(DesignSystem.Colors.warningAmber)
                    Text("Unsaved changes")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.warningAmber)
                }
            }
        case .saved:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.Colors.successGreen)
                Text("Saved")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.successGreen)
            }
        case .error(let message):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.Colors.errorRed)
                Text(message)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.errorRed)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var connectionStatusIndicator: some View {
        switch viewModel.connectionTestState {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("Testing...")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        case .success:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.Colors.successGreen)
                Text(viewModel.connectionSuccessMessage)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.successGreen)
                    .lineLimit(2)
            }
        case .error(let message):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.Colors.errorRed)
                Text(message)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.errorRed)
                    .lineLimit(2)
            }
        }
    }
}

private struct AIFormatterActivationToggle: View {
    @Binding var isOn: Bool
    let isAvailable: Bool
    let disabledReason: String?

    var body: some View {
        Toggle("AI Formatter", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(AIFormatterActivationToggleStyle())
            .disabled(!isAvailable)
            .help(disabledReason ?? "Run AI formatting after the standard cleanup step.")
            .accessibilityLabel("AI Formatter")
            .accessibilityValue(isOn ? "Enabled" : "Disabled")
            .accessibilityHint(disabledReason ?? "Runs after local transcription cleanup as the final output step.")
    }
}

private struct AIFormatterActivationToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: configuration.isOn ? "sparkles" : "wand.and.stars")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconTint(isOn: configuration.isOn))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(iconBackground(isOn: configuration.isOn))
                    )
                    .accessibilityHidden(true)

                Text(labelText(isOn: configuration.isOn))
                    .font(DesignSystem.Typography.caption.weight(.semibold))
                    .foregroundStyle(labelTint(isOn: configuration.isOn))
                    .lineLimit(1)

                Spacer(minLength: 4)

                switchTrack(isOn: configuration.isOn)
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .frame(width: 164, height: 38)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                    .fill(controlBackground(isOn: configuration.isOn))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                    .strokeBorder(controlBorder(isOn: configuration.isOn), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius))
        }
        .buttonStyle(.plain)
    }

    private func switchTrack(isOn: Bool) -> some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(trackBackground(isOn: isOn))
                .overlay(
                    Capsule()
                        .strokeBorder(trackBorder(isOn: isOn), lineWidth: 1)
                )

            Circle()
                .fill(knobFill(isOn: isOn))
                .frame(width: 14, height: 14)
                .padding(2)
                .shadow(color: .black.opacity(isOn && isEnabled ? 0.18 : 0), radius: 2, y: 1)
        }
        .frame(width: 34, height: 18)
        .accessibilityHidden(true)
    }

    private func labelText(isOn: Bool) -> String {
        guard isEnabled else { return "Unavailable" }
        return isOn ? "Enabled" : "Enable"
    }

    private func iconTint(isOn: Bool) -> Color {
        if !isEnabled { return DesignSystem.Colors.textTertiary }
        return isOn ? DesignSystem.Colors.onAccent : DesignSystem.Colors.accent
    }

    private func iconBackground(isOn: Bool) -> Color {
        if !isEnabled { return DesignSystem.Colors.surfaceElevated.opacity(0.75) }
        return isOn ? DesignSystem.Colors.accent : DesignSystem.Colors.accent.opacity(0.12)
    }

    private func labelTint(isOn: Bool) -> Color {
        if !isEnabled { return DesignSystem.Colors.textTertiary }
        return isOn ? DesignSystem.Colors.accentDark : DesignSystem.Colors.textSecondary
    }

    private func controlBackground(isOn: Bool) -> Color {
        if !isEnabled { return DesignSystem.Colors.surfaceElevated.opacity(0.45) }
        return isOn ? DesignSystem.Colors.accentLight : DesignSystem.Colors.surfaceElevated
    }

    private func controlBorder(isOn: Bool) -> Color {
        if !isEnabled { return DesignSystem.Colors.border.opacity(0.45) }
        return isOn ? DesignSystem.Colors.accent.opacity(0.45) : DesignSystem.Colors.border.opacity(0.75)
    }

    private func trackBackground(isOn: Bool) -> Color {
        if !isEnabled { return DesignSystem.Colors.border.opacity(0.35) }
        return isOn ? DesignSystem.Colors.accent : DesignSystem.Colors.border.opacity(0.35)
    }

    private func trackBorder(isOn: Bool) -> Color {
        if !isEnabled { return Color.clear }
        return isOn ? DesignSystem.Colors.accent.opacity(0.35) : DesignSystem.Colors.border.opacity(0.75)
    }

    private func knobFill(isOn: Bool) -> Color {
        if !isEnabled { return DesignSystem.Colors.textTertiary.opacity(0.55) }
        return isOn ? DesignSystem.Colors.onAccent : DesignSystem.Colors.textSecondary
    }
}
