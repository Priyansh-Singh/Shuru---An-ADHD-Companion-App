import Foundation
import CoreLocation

/// Geofences for "When I get home"-style routines.
/// iOS watches the places itself (no server, no constant GPS) and wakes Shuru when you arrive.
final class Places: NSObject, CLLocationManagerDelegate {
    static let shared = Places()

    private let manager = CLLocationManager()
    private var pendingFix: ((CLLocation?) -> Void)?
    private static let prefix = "shuru.place."

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }

    var canWatchInBackground: Bool { manager.authorizationStatus == .authorizedAlways }

    /// One location fix for "Use my current location". Asks for permission first if needed.
    func requestCurrentLocation(_ done: @escaping (CLLocation?) -> Void) {
        pendingFix = done
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(nil)
        default:
            manager.requestLocation()
        }
    }

    /// Region monitoring only works in the background with "Always".
    func askForAlways() {
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }

    /// Watches every enabled routine that has a saved place.
    func sync(routines: [Routine]) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        var wanted: [String: CLCircularRegion] = [:]
        for r in routines where r.enabled && r.trigger.kind == .place {
            guard let p = r.trigger.place else { continue }
            let id = Places.prefix + r.id.uuidString
            let radius = min(max(p.radius, 100), manager.maximumRegionMonitoringDistance)
            let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude),
                                          radius: radius, identifier: id)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            wanted[id] = region
            if wanted.count >= 18 { break }
        }
        for region in manager.monitoredRegions where region.identifier.hasPrefix(Places.prefix) {
            if let w = wanted[region.identifier], let current = region as? CLCircularRegion,
               current.center.latitude == w.center.latitude, current.center.longitude == w.center.longitude,
               current.radius == w.radius {
                wanted[region.identifier] = nil
            } else {
                manager.stopMonitoring(for: region)
            }
        }
        for region in wanted.values {
            manager.startMonitoring(for: region)
        }
    }

    private func finish(_ location: CLLocation?) {
        let done = pendingFix
        pendingFix = nil
        DispatchQueue.main.async { done?(location) }
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard pendingFix != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            finish(nil)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if pendingFix != nil { finish(locations.last) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if pendingFix != nil { finish(nil) }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier.hasPrefix(Places.prefix),
              let id = UUID(uuidString: String(region.identifier.dropFirst(Places.prefix.count))) else { return }
        DispatchQueue.main.async {
            AppStore.shared.cueHappened(routineID: id, announce: true, automatic: true)
        }
    }
}
