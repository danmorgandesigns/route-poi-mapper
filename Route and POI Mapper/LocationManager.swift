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
    
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isTracking = false
    @Published var isPaused = false
    
    // Route tracking
    @Published var currentRoute: [TrailCoordinate] = []
    @Published var currentSegments: [[[Double]]] = [] // MultiLineString segments: [ [ [lon, lat, elev], ... ], ... ]
    private var currentSegment: [[Double]] = []
    @Published var routeStartTime: Date?
    
    // Error handling
    @Published var errorMessage: String?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 2 // More precise for hiking trails
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
        locationManager.startUpdatingLocation()
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
    }
    
    func stopRouteTracking() {
        isTracking = false
        isPaused = false
        if !currentSegment.isEmpty {
            currentSegments.append(currentSegment)
            currentSegment.removeAll()
        }
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
                    // Simple distance filter: only append if moved > 3 meters from last point in currentSegment
                    if let last = currentSegment.last {
                        let dLon = lon - last[0]
                        let dLat = lat - last[1]
                        let approxMeters = sqrt(dLon*dLon + dLat*dLat) * 111_000.0
                        if approxMeters > 3.0 {
                            currentSegment.append([lon, lat, elev])
                        }
                    } else {
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
                manager.startUpdatingLocation()
            @unknown default:
                break
            }
        }
    }
}

