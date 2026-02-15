import Foundation

struct FrameThrottler: Sendable {
    let interval: TimeInterval

    private let lastTime: UnsafeSendableBox<CFAbsoluteTime>

    init(fps: Double = 7) {
        self.interval = 1.0 / fps
        self.lastTime = UnsafeSendableBox(0)
    }

    func shouldProcess() -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastTime.value >= interval {
            lastTime.value = now
            return true
        }
        return false
    }
}

final class UnsafeSendableBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
