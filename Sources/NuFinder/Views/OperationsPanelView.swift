import SwiftUI

/// Fork: panel de operaciones de archivo rehecho (sustituye a TransferDetailsView del autor).
/// - Opciones en su propia fila, textos alineados y botones que caben.
/// - Se cierra solo cuando todas las operaciones terminan bien (si hay un error, se queda abierto).
struct OperationsPanelView: View {
    @EnvironmentObject private var operations: FileOperationManager
    @AppStorage("operations.autoClose") private var autoClose = true
    @State private var wasRunning = false
    private let formatter = ByteCountFormatter()

    private var isRunning: Bool { operations.operations.contains { $0.finishedAt == nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(16)
            Divider()
            if operations.operations.isEmpty {
                ContentUnavailableView("No File Operations", systemImage: "arrow.left.arrow.right")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(operations.operations) { operation in
                            row(operation)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 600, idealWidth: 640, minHeight: 360, idealHeight: 420)
        .onAppear { wasRunning = isRunning }
        .onChange(of: isRunning) { _, running in
            if running { wasRunning = true; return }
            guard wasRunning, autoClose else { return }
            wasRunning = false
            let finishedWithProblems = operations.operations.prefix(5).contains { $0.error != nil }
            guard !finishedWithProblems else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if !isRunning { operations.showsDetails = false }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("File Operations").font(.title2.bold())
                Spacer()
                Button("Clear Completed") { operations.clearCompleted() }
                Button("Done") { operations.showsDetails = false }
                    .keyboardShortcut(.defaultAction)
            }
            HStack(spacing: 20) {
                LabeledContent("When an item exists") {
                    Picker("When an item exists", selection: $operations.conflictPolicy) {
                        ForEach(ConflictPolicy.allCases) { policy in
                            Text(LocalizedStringKey(policy.rawValue)).tag(policy)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                LabeledContent("Concurrent") {
                    Picker("Concurrent", selection: $operations.maxConcurrentOperations) {
                        ForEach(1...4, id: \.self) { Text(verbatim: "\($0)").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Spacer()
                Toggle("Close when finished", isOn: $autoClose)
                    .toggleStyle(.checkbox)
            }
            .font(.callout)
        }
    }

    private func row(_ operation: FileOperation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: operation.isMove ? "arrow.right.doc.on.clipboard" : "doc.on.doc")
                    .foregroundStyle(.secondary)
                Text(operation.isMove ? LocalizedStringKey("Moving") : LocalizedStringKey("Copying"))
                    .font(.headline)
                Text(operation.sourceNames.joined(separator: ", "))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                status(operation)
                    .layoutPriority(1)
            }
            if operation.finishedAt == nil || operation.error != nil {
                ProgressView(value: operation.progress)
            }
            HStack(spacing: 8) {
                Text("To: \(operation.destination.path)")
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(operation.destination.path)
                Text("\(formatter.string(fromByteCount: operation.completedBytes)) of \(formatter.string(fromByteCount: operation.totalBytes))")
                    .monospacedDigit()
                    .fixedSize()
                if operation.finishedAt == nil && !operation.isQueued {
                    Text(verbatim: "· \(formatter.string(fromByteCount: Int64(operation.bytesPerSecond)))/s")
                        .monospacedDigit()
                        .fixedSize()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let error = operation.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions(operation)
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func actions(_ operation: FileOperation) -> some View {
        if operation.isQueued {
            HStack(spacing: 8) {
                Button { operations.moveQueued(operation.id, by: -1) } label: { Image(systemName: "arrow.up") }
                    .help(Text("Move Up"))
                Button { operations.moveQueued(operation.id, by: 1) } label: { Image(systemName: "arrow.down") }
                    .help(Text("Move Down"))
                Spacer()
                Button("Cancel", role: .destructive) { operations.cancel(operation.id) }
            }
            .controlSize(.small)
        } else if operation.finishedAt == nil {
            HStack(spacing: 8) {
                Spacer()
                Button(operation.isPaused ? LocalizedStringKey("Resume") : LocalizedStringKey("Pause")) {
                    operations.togglePause(operation.id)
                }
                Button("Cancel", role: .destructive) { operations.cancel(operation.id) }
            }
            .controlSize(.small)
        } else if operation.error != nil || operation.isCancelled {
            HStack {
                Spacer()
                Button("Retry") { operations.retry(operation.id) }
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func status(_ operation: FileOperation) -> some View {
        if operation.error != nil {
            Label("Failed", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        } else if operation.isQueued {
            Label("Queued", systemImage: "clock").foregroundStyle(.secondary)
        } else if operation.isCancelled {
            Label("Cancelled", systemImage: "xmark.circle.fill").foregroundStyle(.orange)
        } else if operation.finishedAt != nil {
            Label("Complete", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else if operation.isPaused {
            Label("Paused", systemImage: "pause.circle.fill").foregroundStyle(.orange)
        } else {
            Text(operation.currentItem).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 160, alignment: .trailing)
        }
    }
}
