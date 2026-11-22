import Foundation
import HomeDriveCore
import Observation

/// One upload or download shown in the transfers list.
@MainActor
@Observable
final class Transfer: Identifiable {
    enum Direction {
        case upload, download
    }

    enum State: Equatable {
        case queued, running, done, failed(String), cancelled

        var isFinished: Bool {
            switch self {
            case .done, .failed, .cancelled: return true
            case .queued, .running: return false
            }
        }
    }

    typealias Job = @Sendable (_ progress: @escaping @Sendable (Int64) -> Void) async throws -> Void

    let id = UUID()
    let name: String
    let direction: Direction
    /// Human-readable destination, e.g. `~/Documents` on the PC.
    let destination: String
    /// Where the result ends up on the Mac (downloads only), for "Show in Finder".
    let localResult: URL?
    var totalBytes: Int64
    private(set) var transferred: Int64 = 0
    private(set) var state: State = .queued
    private(set) var startedAt: Date?
    private(set) var finishedAt: Date?

    @ObservationIgnored let job: Job
    @ObservationIgnored var onSuccess: (@MainActor () -> Void)?
    @ObservationIgnored var onFinish: (@MainActor () -> Void)?
    @ObservationIgnored fileprivate var task: Task<Void, Never>?

    init(name: String, direction: Direction, destination: String, localResult: URL? = nil,
         totalBytes: Int64, job: @escaping Job) {
        self.name = name
        self.direction = direction
        self.destination = destination
        self.localResult = localResult
        self.totalBytes = totalBytes
        self.job = job
    }

    /// 0...1, or nil when the size is unknown.
    var fraction: Double? {
        if state == .done { return 1 }
        guard totalBytes > 0 else { return nil }
        return min(1, Double(transferred) / Double(totalBytes))
    }

    /// Average bytes per second since the transfer started.
    var bytesPerSecond: Double? {
        guard let startedAt else { return nil }
        let elapsed = (finishedAt ?? Date()).timeIntervalSince(startedAt)
        guard elapsed > 0.5 else { return nil }
        return Double(transferred) / elapsed
    }

    var secondsRemaining: Double? {
        guard state == .running, let speed = bytesPerSecond, speed > 0, totalBytes > transferred else { return nil }
        return Double(totalBytes - transferred) / speed
    }

    fileprivate func start() {
        state = .running
        startedAt = Date()
    }

    fileprivate func report(_ bytes: Int64) {
        guard state == .running else { return }
        // tar adds a little overhead (headers, padding), so the stream can be slightly larger
        // than the files themselves. Clamp so the UI never shows "11 MB of 10 MB".
        transferred = totalBytes > 0 ? min(bytes, totalBytes) : bytes
    }

    fileprivate func finish(_ newState: State) {
        state = newState
        finishedAt = Date()
    }
}

/// Runs transfers a couple at a time and keeps the finished ones around for display.
@MainActor
@Observable
final class TransferQueue {
    private(set) var items: [Transfer] = []
    var maxConcurrent = 2

    var activeCount: Int { items.filter { !$0.state.isFinished }.count }
    var hasFinished: Bool { items.contains { $0.state.isFinished } }

    func enqueue(_ transfer: Transfer) {
        items.append(transfer)
        pump()
    }

    func cancel(_ transfer: Transfer) {
        switch transfer.state {
        case .queued:
            transfer.finish(.cancelled)
            transfer.onFinish?()
        case .running:
            transfer.task?.cancel()
        default:
            break
        }
    }

    func cancelAll() {
        items.forEach(cancel)
    }

    func clearFinished() {
        items.removeAll { $0.state.isFinished }
    }

    func remove(_ transfer: Transfer) {
        guard transfer.state.isFinished else { return }
        items.removeAll { $0.id == transfer.id }
    }

    private func pump() {
        let running = items.filter { $0.state == .running }.count
        guard running < maxConcurrent,
              let next = items.first(where: { $0.state == .queued }) else { return }
        next.start()
        let job = next.job
        next.task = Task { [weak self] in
            let reporter: @Sendable (Int64) -> Void = { bytes in
                Task { @MainActor in next.report(bytes) }
            }
            let outcome: Transfer.State
            do {
                try await job(reporter)
                outcome = .done
            } catch is CancellationError {
                outcome = .cancelled
            } catch {
                outcome = .failed(error.localizedDescription)
            }
            // Let any last progress update land before the final state.
            await Task.yield()
            next.finish(outcome)
            if outcome == .done { next.onSuccess?() }
            next.onFinish?()
            self?.pump()
        }
        pump()
    }
}
