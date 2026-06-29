import AppKit
import DarkbloomCore
import SwiftUI

enum ServingPickerIntent {
    case start
    case restart

    var title: String {
        switch self {
        case .start: return "Start serving"
        case .restart: return "Restart serving"
        }
    }

    var subtitle: String {
        switch self {
        case .start: return "Choose the models this Mac should serve."
        case .restart: return "Update the served models and relaunch the provider."
        }
    }

    var actionLabel: String {
        switch self {
        case .start: return "Start"
        case .restart: return "Restart"
        }
    }

    var actionIcon: String {
        switch self {
        case .start: return "play.fill"
        case .restart: return "arrow.clockwise"
        }
    }
}

struct ServingModelPickerView: View {
    var intent: ServingPickerIntent
    var models: [CoordinatorAPI.CatalogModel]
    var physicalMemoryGB: Double
    var downloadedModels: Set<String>
    @Binding var selectedModels: Set<String>
    @Binding var prewarmAfterRestart: Bool
    var cancel: () -> Void
    var commit: ([String], Bool) -> Void

    @FocusState private var pickerFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if models.isEmpty {
                EmptyModelCatalogView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(models) { model in
                            modelRow(model)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .frame(maxHeight: 230)
            }

            if !unavailableSelectedModels.isEmpty {
                Label("Remove unavailable models before \(intent.actionLabel.lowercased()).", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Toggle("Always pre-warm selected models", isOn: $prewarmAfterRestart)
                .font(.caption)
                .toggleStyle(.checkbox)

            footer
        }
        .padding(12)
        .focusable()
        .focused($pickerFocused)
        .onAppear {
            pickerFocused = true
        }
        .onExitCommand(perform: cancel)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.green.opacity(0.14))
                Image(systemName: intent.actionIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(intent.title)
                    .font(.callout.weight(.semibold))
                Text(intent.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Text(selectionCountText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Cancel", action: cancel)
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button {
                commit(commitSelection, prewarmAfterRestart)
            } label: {
                Label(intent.actionLabel, systemImage: intent.actionIcon)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(commitSelection.isEmpty || !unavailableSelectedModels.isEmpty)
        }
        .controlSize(.small)
    }

    private func modelRow(_ model: CoordinatorAPI.CatalogModel) -> some View {
        let selected = selectedModels.contains(model.id)
        let fits = modelFits(model)
        let downloaded = downloadedModels.contains(model.id)

        return Toggle(isOn: selectionBinding(for: model.id, allowsSelection: fits)) {
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(fits ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(modelCaption(model, fits: fits, downloaded: downloaded))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 6)

                HStack(spacing: 4) {
                    if downloaded {
                        ModelBadge(text: "Local", color: .green)
                    } else if fits {
                        ModelBadge(text: "Download", color: .secondary)
                    }
                    if !fits {
                        ModelBadge(text: "Too large", color: .orange)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                selected ? Color.green.opacity(0.10) : Color(nsColor: .controlBackgroundColor).opacity(0.60),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        selected ? Color.green.opacity(0.35) : Color(nsColor: .separatorColor).opacity(0.30),
                        lineWidth: 1
                    )
            }
        }
        .toggleStyle(.checkbox)
        .disabled(!fits && !selected)
        .opacity(fits ? 1 : 0.55)
        .accessibilityLabel(model.displayName)
        .accessibilityValue(fits ? (selected ? "Selected" : "Not selected") : "Unavailable")
        .accessibilityHint(fits ? modelCaption(model, fits: fits, downloaded: downloaded) : "This model needs more memory than this Mac has.")
        .help(modelCaption(model, fits: fits, downloaded: downloaded))
    }

    private var selectionCountText: String {
        switch selectedModels.count {
        case 0: return "None"
        case 1: return "1 model"
        default: return "\(selectedModels.count) models"
        }
    }

    private var commitSelection: [String] {
        models
            .filter { selectedModels.contains($0.id) && modelFits($0) }
            .map(\.id)
    }

    private var unavailableSelectedModels: [CoordinatorAPI.CatalogModel] {
        models.filter { selectedModels.contains($0.id) && !modelFits($0) }
    }

    private func selectionBinding(for id: String, allowsSelection: Bool) -> Binding<Bool> {
        Binding {
            selectedModels.contains(id)
        } set: { selected in
            guard allowsSelection || !selected else { return }
            if selected {
                selectedModels.insert(id)
            } else {
                selectedModels.remove(id)
            }
        }
    }

    private func modelFits(_ model: CoordinatorAPI.CatalogModel) -> Bool {
        (model.minRamGB ?? 0) <= physicalMemoryGB
    }

    private func modelCaption(_ model: CoordinatorAPI.CatalogModel, fits: Bool, downloaded: Bool) -> String {
        var parts: [String] = []
        if let size = model.sizeGB {
            parts.append(String(format: "%.1f GB", size))
        }
        if let ram = model.minRamGB {
            parts.append(fits ? String(format: "needs %.0f GB RAM", ram)
                              : String(format: "needs %.0f GB RAM, unavailable here", ram))
        }
        if downloaded {
            parts.append("downloaded")
        }
        return parts.isEmpty ? model.id : parts.joined(separator: " - ")
    }
}

private struct ModelBadge: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct EmptyModelCatalogView: View {
    var body: some View {
        Label("Model catalog unavailable", systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.60), in: RoundedRectangle(cornerRadius: 9))
    }
}
