import Foundation
import Network
import Observation

@MainActor
@Observable
final class ConnectivityMonitor {
    private(set) var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.myapp.connectivity")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isConnected = path.status == .satisfied
            let owner = self
            Task { @MainActor in
                owner?.isConnected = isConnected
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

func isNetworkUnavailable(_ error: Error) -> Bool {
    guard let urlError = error as? URLError else { return false }
    switch urlError.code {
    case .notConnectedToInternet,
         .networkConnectionLost,
         .timedOut,
         .cannotFindHost,
         .cannotConnectToHost,
         .dnsLookupFailed,
         .internationalRoamingOff,
         .dataNotAllowed:
        return true
    default:
        return false
    }
}
