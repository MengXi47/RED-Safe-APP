import Foundation
import Network

// MARK: - Network Monitor

/// 封裝 NWPathMonitor，以 @Observable 發布即時網路連線狀態供全 App 使用。
@MainActor @Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    // MARK: - Public State

    private(set) var isConnected: Bool = true
    private(set) var connectionType: ConnectionType = .unknown

    enum ConnectionType: String {
        case wifi
        case cellular
        case wiredEthernet
        case unknown
    }

    // MARK: - AsyncStream

    /// 訂閱後立即發出當前狀態，之後每當 isConnected 改變時發出新值。
    var connectivityUpdates: AsyncStream<Bool> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.yield(isConnected)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let monitor = NWPathMonitor()
        self.monitor = monitor

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.handlePathUpdate(path)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        isRunning = false
    }

    // MARK: - Wait for Connectivity

    /// 等待網路恢復連線，最多等待 `timeout` 秒。回傳是否成功恢復。
    func waitForConnectivity(timeout: TimeInterval = 30) async -> Bool {
        if isConnected { return true }

        let id = UUID()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let timeoutTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    guard self.waiters.removeValue(forKey: id) != nil else { return }
                    self.pendingContinuations.removeValue(forKey: id)?.resume(returning: false)
                }
                waiters[id] = timeoutTask
                pendingContinuations[id] = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let task = self.waiters.removeValue(forKey: id)
                task?.cancel()
                self.pendingContinuations.removeValue(forKey: id)?.resume(returning: false)
            }
        }
    }

    // MARK: - Private

    private var monitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.redsafe.networkmonitor", qos: .utility)
    private var isRunning = false
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]
    private var waiters: [UUID: Task<Void, Never>] = [:]
    private var pendingContinuations: [UUID: CheckedContinuation<Bool, Never>] = [:]

    private init() {}

    private func handlePathUpdate(_ path: NWPath) {
        let newConnected = path.status == .satisfied
        let newType = resolveConnectionType(path)

        let changed = newConnected != isConnected
        isConnected = newConnected
        connectionType = newType

        if changed {
            for (_, continuation) in continuations {
                continuation.yield(newConnected)
            }

            // 喚醒所有等待連線的 waiter
            if newConnected {
                let pendingTasks = waiters
                let pending = pendingContinuations
                waiters.removeAll()
                pendingContinuations.removeAll()
                for (id, task) in pendingTasks {
                    task.cancel()
                    pending[id]?.resume(returning: true)
                }
            }
        }
    }

    private func resolveConnectionType(_ path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.usesInterfaceType(.wiredEthernet) { return .wiredEthernet }
        return .unknown
    }
}
