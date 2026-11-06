import Foundation

enum HealthReadingQueryFailure: Error { case timeout }

/// Own one query and its continuation. Cancellation before start never executes
/// it; cancellation during registration waits for start to return, then stops
/// it before resuming. Synchronous and late callbacks can finish only once.
final class HealthReadingQuery<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var outcome: Result<Value, Error>?
    private var used = false
    private var starting = false
    private var stopping = false
    private var stop: (@Sendable () -> Void)?
    private var timer: DispatchWorkItem?

    func value(timeout: TimeInterval = 30, start: () -> Void,
               stop: @escaping @Sendable () -> Void) async throws -> Value {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                precondition(!used, "A Health query has one awaiting owner")
                used = true
                if let outcome {
                    lock.unlock(); continuation.resume(with: outcome); return
                }
                self.continuation = continuation; self.stop = stop; starting = true
                lock.unlock()
                start()
                lock.lock(); starting = false
                let delivery = takeDelivery()
                if outcome == nil {
                    let timer = DispatchWorkItem { [weak self] in self?.expire() }
                    self.timer = timer
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timer)
                }
                lock.unlock()
                deliver(delivery)
            }
        } onCancel: { self.cancel() }
    }

    func complete(_ result: Result<Value, Error>) { finish(result, stopping: false) }
    func cancel() { finish(.failure(CancellationError()), stopping: true) }
    func expire() { finish(.failure(HealthReadingQueryFailure.timeout), stopping: true) }

    private typealias Delivery = (CheckedContinuation<Value, Error>, Result<Value, Error>, (@Sendable () -> Void)?)
    private func takeDelivery() -> Delivery? {
        guard !starting, let outcome, let continuation else { return nil }
        self.continuation = nil
        let stop = stopping ? self.stop : nil
        self.stop = nil; timer?.cancel(); timer = nil
        return (continuation, outcome, stop)
    }
    private func finish(_ result: Result<Value, Error>, stopping: Bool) {
        lock.lock()
        guard outcome == nil else { lock.unlock(); return }
        outcome = result; self.stopping = stopping
        let delivery = takeDelivery()
        lock.unlock()
        deliver(delivery)
    }
    private func deliver(_ delivery: Delivery?) {
        guard let (continuation, result, stop) = delivery else { return }
        stop?()
        continuation.resume(with: result)
    }
}

/// A today request owns all eighteen query handles, rather than sharing one
/// mutable cancellation slot or leaving sibling queries running after Back.
final class HealthReadingQueryGroup: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var callbacks: [UUID: @Sendable () -> Void] = [:]
    func register(_ callback: @escaping @Sendable () -> Void) -> UUID {
        let id = UUID()
        lock.lock(); let cancelled = self.cancelled
        if !cancelled { callbacks[id] = callback }
        lock.unlock()
        if cancelled { callback() }
        return id
    }
    func detach(_ id: UUID) { lock.lock(); callbacks.removeValue(forKey: id); lock.unlock() }
    func cancel() {
        lock.lock(); cancelled = true; let callbacks = Array(self.callbacks.values); self.callbacks = [:]; lock.unlock()
        callbacks.forEach { $0() }
    }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func checkCancellation() throws { if isCancelled || Task.isCancelled { throw CancellationError() } }
}
