import HomeDriveCore
import SwiftUI

/// The list of uploads/downloads at the bottom of the window.
struct TransfersView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let queue = app.transfers
        VStack(spacing: 0) {
            HStack {
                Text("Transfers").font(.headline)
                if queue.activeCount > 0 {
                    Text("\(queue.activeCount) in progress").foregroundStyle(.secondary)
                }
                Spacer()
                if queue.activeCount > 0 {
                    Button("Cancel All") { queue.cancelAll() }
                }
                Button("Clear Finished") { queue.clearFinished() }
                    .disabled(!queue.hasFinished)
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            if queue.items.isEmpty {
                Text("Select files and use Send / Retrieve, or drag them between the two sides.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(queue.items.reversed()) { transfer in
                        TransferRow(transfer: transfer)
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct TransferRow: View {
    @Environment(AppModel.self) private var app
    let transfer: Transfer

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: transfer.direction == .upload ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.title2)
                .foregroundStyle(transfer.direction == .upload ? Color.orange : Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(transfer.name).lineLimit(1).truncationMode(.middle)
                    Text(transfer.direction == .upload ? "→ PC \(transfer.destination)" : "→ Mac \(transfer.destination)")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                switch transfer.state {
                case .queued:
                    ProgressView(value: 0).progressViewStyle(.linear)
                    detail("Waiting…")
                case .running:
                    if let fraction = transfer.fraction {
                        ProgressView(value: fraction).progressViewStyle(.linear)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                    detail(runningDetail)
                case .done:
                    detail("Done · \(Format.bytes(transfer.totalBytes > 0 ? transfer.totalBytes : transfer.transferred))"
                           + (transfer.bytesPerSecond.map { " · \(Format.speed($0))" } ?? ""))
                case .failed(let message):
                    Text(message).font(.caption).foregroundStyle(.red).lineLimit(3).textSelection(.enabled)
                case .cancelled:
                    detail("Cancelled")
                }
            }
            Spacer()
            actions
        }
        .padding(.vertical, 2)
    }

    private var runningDetail: String {
        var parts = [Format.bytes(transfer.transferred)
                     + (transfer.totalBytes > 0 ? " of \(Format.bytes(transfer.totalBytes))" : "")]
        if let speed = transfer.bytesPerSecond { parts.append(Format.speed(speed)) }
        if let remaining = transfer.secondsRemaining { parts.append("\(Format.duration(remaining)) left") }
        return parts.joined(separator: " · ")
    }

    private func detail(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).monospacedDigit()
    }

    @ViewBuilder
    private var actions: some View {
        if !transfer.state.isFinished {
            Button { app.transfers.cancel(transfer) } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Cancel")
        } else {
            if transfer.state == .done, let url = transfer.localResult {
                Button { app.revealLocal(url) } label: { Image(systemName: "magnifyingglass.circle.fill") }
                    .buttonStyle(.borderless)
                    .help("Show in Finder")
            }
            Button { app.transfers.remove(transfer) } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove from list")
        }
    }
}
