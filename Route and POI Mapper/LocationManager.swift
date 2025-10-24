//
//  LocationManager.swift
//  Route and POI Mapper
//
//  Created by Dan Morgan on 10/10/25.
//

import Foundation
import CoreLocation
import Combine

@MainActor
class LocationManager: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()
    private var hasConfiguredForBackground = false
    
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isTracking = false
    @Published var isPaused = false
    @Published var isFinalizingLastPoint: Bool = false
    
    // Route tracking
    @Published var currentRoute: [TrailCoordinate] = []
    @Published var currentSegments: [[[Double]]] = [] // MultiLineString segments: [ [ [lon, lat, elev], ... ], ... ]
    private var currentSegment: [[Double]] = []
    @Published var routeStartTime: Date?
    private var hasRecordedFirstPoint = false
    private var forceFirstPointOnResume = false
    
    // Buffer for recent samples used for final fix fallback
    private var recentSamples: [CLLocation] = []
    private let recentBufferMax = 10
    
    // Temporary sample handler for captureFinalFix
    private var onTemporarySample: ((CLLocation) -> Void)? = nil
    
    // Error handling
    @Published var errorMessage: String?
    
    private var routePrecisionMeters: Double {
        let value = UserDefaults.standard.double(forKey: "routePrecisionMeters")
        // If key is not set, double(forKey:) returns 0.0; provide default 5.0
        return value > 0 ? value : 5.0
    }
    
    private var updateFrequencyMeters: Double {
        let value = UserDefaults.standard.double(forKey: "updateFrequencyMeters")
        // If key is not set, fall back to 10.0
        return value > 0 ? value : 10.0
    }
    
    override init() {
        super.init()
        locationManager.delegate = self
        // Configure for high accuracy and background coexistence
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 2 // prefer fine-grained points for accurate routes
        locationManager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = locationManager.authorizationStatus
        
        // Request permission on launch if not determined; start updates if already authorized
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        default:
            break
        }
    }
    
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startRouteTracking() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            errorMessage = "Location permission is required to track routes"
            return
        }
        
        currentRoute.removeAll()
        currentSegments.removeAll()
        currentSegment.removeAll()
        isPaused = false
        routeStartTime = Date()
        isTracking = true
        hasRecordedFirstPoint = false
        
        // Record the current location immediately if available, accurate, and recent
        if let currentLocation = location,
           currentLocation.horizontalAccuracy > 0,
           abs(currentLocation.timestamp.timeIntervalSinceNow) > -15 { // within last 15 seconds
            let trailCoordinate = TrailCoordinate(from: currentLocation)
            currentRoute.append(trailCoordinate)
            let lon = currentLocation.coordinate.longitude
            let lat = currentLocation.coordinate.latitude
            let elev = currentLocation.altitude
            currentSegment.append([lon, lat, elev])
            hasRecordedFirstPoint = true
        }
        
        // Enable background updates if capability is present
        if !hasConfiguredForBackground {
            locationManager.allowsBackgroundLocationUpdates = true
            // Keep system from auto-pausing during short, high-accuracy sessions
            locationManager.pausesLocationUpdatesAutomatically = false
            hasConfiguredForBackground = true
        }
        
        // Prefer Always authorization for reliable background tracking
        if authorizationStatus == .authorizedWhenInUse {
            // On iOS, you must explicitly request Always after When-In-Use, ideally after explaining to the user
            locationManager.requestAlwaysAuthorization()
        }
        
        
        // Temporarily set minimal distance filter for immediate responsiveness
        locationManager.distanceFilter = 0 // No distance filter to catch first point immediately
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
        locationManager.pausesLocationUpdatesAutomatically = false
        
        locationManager.startUpdatingLocation()
        
        // Request an immediate location update to ensure we get the starting point quickly
        locationManager.requestLocation()
        
        // Schedule restoration of user's distance filter after a brief delay
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            await MainActor.run {
                if isTracking {
                    locationManager.distanceFilter = updateFrequencyMeters
                }
            }
        }
    }
    
    func pauseRouteTracking() {
        guard isTracking, !isPaused else { return }
        isPaused = true
        isFinalizingLastPoint = true
        
        Task {
            let finalFix = await captureFinalFix(timeout: 3, minAccuracy: routePrecisionMeters)
            
            if let loc = finalFix {
                await MainActor.run(body: {
                    appendIfNotDuplicate(loc)
                })
            } else if let recentLoc = await MainActor.run(resultType: CLLocation?.self, body: { bestRecentSample(minAccuracy: routePrecisionMeters) }) {
                await MainActor.run(body: {
                    appendIfNotDuplicate(recentLoc)
                })
            }
            
            await MainActor.run {
                if !currentSegment.isEmpty {
                    currentSegments.append(currentSegment)
                    currentSegment.removeAll()
                }
                isFinalizingLastPoint = false
            }
        }
    }
    
    func resumeRouteTracking() {
        guard isTracking, isPaused else { return }
        isPaused = false
        
        // Force the first point of the new segment - ensure we get a fresh location
        forceFirstPointOnResume = true
        
        // Configure for immediate, high-accuracy location acquisition
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone // No filtering for immediate response
        locationManager.pausesLocationUpdatesAutomatically = false
        
        // Start updates immediately - don't use requestLocation() as it can conflict
        locationManager.startUpdatingLocation()
        
        // Restore user's preferred distance filter after brief delay to ensure first point is captured
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // Reduced to 1 second
            await MainActor.run {
                if isTracking && !isPaused {
                    locationManager.desiredAccuracy = kCLLocationAccuracyBest
                    locationManager.distanceFilter = updateFrequencyMeters
                }
            }
        }
    }
    
    func stopRouteTracking() {
        isFinalizingLastPoint = true
        
        Task {
            let finalFix = await captureFinalFix(timeout: 3, minAccuracy: routePrecisionMeters)
            
            await MainActor.run {
                if let loc = finalFix {
                    appendIfNotDuplicate(loc)
                } else if let recentLoc = bestRecentSample(minAccuracy: routePrecisionMeters) {
                    appendIfNotDuplicate(recentLoc)
                }
                
                isTracking = false
                isPaused = false
                hasRecordedFirstPoint = false
                if !currentSegment.isEmpty {
                    currentSegments.append(currentSegment)
                    currentSegment.removeAll()
                }
                
                // When not actively tracking, relax accuracy to reduce impact (fixed idle distance filter)
                locationManager.activityType = .other
                locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
                locationManager.distanceFilter = 10
                
                // Keep updating location so the blue dot and recentering remain functional
                isFinalizingLastPoint = false
            }
        }
    }
    
    func getCurrentLocation() -> CLLocation? {
        return location
    }
    
    func createTrailRoute(name: String) -> TrailRoute? {
        guard let startTime = routeStartTime, !currentRoute.isEmpty else {
            return nil
        }
        
        return TrailRoute(
            name: name,
            startTime: startTime,
            endTime: Date(),
            coordinates: currentRoute,
            segments: currentSegments.isEmpty ? nil : currentSegments
        )
    }
    
    func exportCurrentRouteGeoJSON(named name: String, color: String? = nil, description: String? = nil, info: String? = nil, imageURL: String? = nil) -> Data? {
        // Finalize any in-progress segment without stopping tracking
        var segments = currentSegments
        if !currentSegment.isEmpty { segments.append(currentSegment) }
        do {
            return try GeoJSONRouteEncoder.makeFeatureCollection(
                name: name,
                segments: segments,
                color: color,
                description: description,
                info: info,
                imageURL: imageURL
            )
        } catch {
            print("[GeoJSON] Export error: \(error)")
            return nil
        }
    }
    
    private func appendIfNotDuplicate(_ loc: CLLocation) {
        let lon = loc.coordinate.longitude
        let lat = loc.coordinate.latitude
        let elev = loc.altitude
        if currentSegment.last.map({ $0[0] != lon || $0[1] != lat }) ?? true {
            currentSegment.append([lon, lat, elev])
        }
    }
    
    private func bestRecentSample(minAccuracy: CLLocationAccuracy, maxAge: TimeInterval = 10) -> CLLocation? {
        let now = Date()
        let validSamples = recentSamples.filter {
            $0.horizontalAccuracy > 0 &&
            $0.horizontalAccuracy <= minAccuracy &&
            now.timeIntervalSince($0.timestamp) <= maxAge
        }
        return validSamples.min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy })
    }
    
    @MainActor func captureFinalFix(timeout: TimeInterval = 3.0, minAccuracy: CLLocationAccuracy) async -> CLLocation? {
        return await withCheckedContinuation { (continuation: CheckedContinuation<CLLocation?, Never>) in
            let originalDesiredAccuracy = locationManager.desiredAccuracy
            let originalDistanceFilter = locationManager.distanceFilter
            var bestLocation: CLLocation?
            var didResume = false

            func resumeOnce(_ location: CLLocation?) {
                Task { @MainActor in
                    guard !didResume else { return }
                    didResume = true
                    onTemporarySample = nil
                    locationManager.desiredAccuracy = originalDesiredAccuracy
                    locationManager.distanceFilter = originalDistanceFilter
                    if !isTracking { locationManager.stopUpdatingLocation() }
                    continuation.resume(returning: location)
                }
            }

            onTemporarySample = { location in
                guard location.horizontalAccuracy > 0 else { return }
                if bestLocation == nil || location.horizontalAccuracy < (bestLocation?.horizontalAccuracy ?? .greatestFiniteMagnitude) {
                    bestLocation = location
                }
                if location.horizontalAccuracy <= minAccuracy {
                    resumeOnce(location)
                }
            }

            locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            locationManager.distanceFilter = kCLDistanceFilterNone
            locationManager.startUpdatingLocation()

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                resumeOnce(bestLocation)
            }
        }
    }
}

@MainActor
extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Allow an initial fix; still ignore invalid readings
        guard location.horizontalAccuracy > 0 else { return }
        
        // Log altitude info for debugging
        print("Location update - Lat: \(location.coordinate.latitude), Lng: \(location.coordinate.longitude), Alt: \(location.altitude), VerticalAccuracy: \(location.verticalAccuracy)")
        
        self.location = location
        
        recentSamples.append(location)
        if recentSamples.count > recentBufferMax {
            recentSamples.removeFirst()
        }
        
        if let handler = onTemporarySample {
            handler(location)
        }
        
        if isTracking {
            let trailCoordinate = TrailCoordinate(from: location)
            currentRoute.append(trailCoordinate)
            if !isPaused {
                let lon = location.coordinate.longitude
                let lat = location.coordinate.latitude
                let elev = location.altitude
                
                // Append points with robust rules: first of route, first after resume, then precision-filtered
                if forceFirstPointOnResume {
                    // Accept the first location after resume regardless of accuracy to avoid delays
                    // The user has moved since pause, so we need a fresh point
                    currentSegment.append([lon, lat, elev])
                    forceFirstPointOnResume = false
                    hasRecordedFirstPoint = true
                } else if !hasRecordedFirstPoint {
                    currentSegment.append([lon, lat, elev])
                    hasRecordedFirstPoint = true
                } else if let last = currentSegment.last {
                    let lastLoc = CLLocation(latitude: last[1], longitude: last[0])
                    let dist = lastLoc.distance(from: location)
                    if dist > routePrecisionMeters {
                        currentSegment.append([lon, lat, elev])
                    }
                } else {
                    currentSegment.append([lon, lat, elev])
                }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = "Location error: \(error.localizedDescription)"
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        
        switch status {
        case .denied, .restricted:
            errorMessage = "Location access denied. Please enable in Settings."
        case .notDetermined:
            break
        case .authorizedWhenInUse, .authorizedAlways:
            errorMessage = nil
            manager.allowsBackgroundLocationUpdates = true
            manager.pausesLocationUpdatesAutomatically = false
            manager.startUpdatingLocation()
        @unknown default:
            break
        }
    }
}

