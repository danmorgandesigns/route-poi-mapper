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
    
    // Route tracking
    @Published var currentRoute: [TrailCoordinate] = []
    @Published var currentSegments: [[[Double]]] = [] // MultiLineString segments: [ [ [lon, lat, elev], ... ], ... ]
    private var currentSegment: [[Double]] = []
    @Published var routeStartTime: Date?
    private var hasRecordedFirstPoint = false
    
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
        
        // Record the current location immediately if available
        if let currentLocation = location {
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
        if !currentSegment.isEmpty {
            currentSegments.append(currentSegment)
            currentSegment.removeAll()
        }
    }
    
    func resumeRouteTracking() {
        guard isTracking, isPaused else { return }
        isPaused = false
        
        // Restore high-accuracy settings for active tracking using user-configured frequency
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = updateFrequencyMeters
        locationManager.pausesLocationUpdatesAutomatically = false
    }
    
    func stopRouteTracking() {
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
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            
            // Allow an initial fix; still ignore invalid readings
            guard location.horizontalAccuracy > 0 else { return }
            
            // Log altitude info for debugging
            print("Location update - Lat: \(location.coordinate.latitude), Lng: \(location.coordinate.longitude), Alt: \(location.altitude), VerticalAccuracy: \(location.verticalAccuracy)")
            
            self.location = location
            
            if isTracking {
                let trailCoordinate = TrailCoordinate(from: location)
                currentRoute.append(trailCoordinate)
                if !isPaused {
                    let lon = location.coordinate.longitude
                    let lat = location.coordinate.latitude
                    let elev = location.altitude
                    
                    // Always record the first point regardless of precision thresholds
                    if !hasRecordedFirstPoint {
                        currentSegment.append([lon, lat, elev])
                        hasRecordedFirstPoint = true
                    } else if let last = currentSegment.last {
                        // Apply precision filtering for subsequent points
                        let dLon = lon - last[0]
                        let dLat = lat - last[1]
                        let approxMeters = sqrt(dLon*dLon + dLat*dLat) * 111_000.0
                        if approxMeters > routePrecisionMeters {
                            currentSegment.append([lon, lat, elev])
                        }
                    } else {
                        // Fallback: if somehow we don't have a last point, add this one
                        currentSegment.append([lon, lat, elev])
                    }
                }
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            errorMessage = "Location error: \(error.localizedDescription)"
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
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
}

