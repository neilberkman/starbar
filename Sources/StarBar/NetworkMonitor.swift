import Foundation
import Network

class NetworkMonitor {
  private let monitor = NWPathMonitor()
  private let queue = DispatchQueue(label: "NetworkMonitor")
  private var lastPath: NWPath?
  var onNetworkChange: (() -> Void)?

  func start() {
    monitor.pathUpdateHandler = { [weak self] path in
      guard let self = self else { return }

      // Only fire callback on actual network changes, not initial state
      if let lastPath = self.lastPath,
         lastPath.status == .satisfied,
         path.status == .satisfied,
         lastPath.availableInterfaces != path.availableInterfaces
      {
        self.onNetworkChange?()
      }

      self.lastPath = path
    }
    monitor.start(queue: queue)
  }

  func stop() {
    monitor.cancel()
  }
}
