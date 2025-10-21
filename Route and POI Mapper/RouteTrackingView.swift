//
//  RouteTrackingView.swift
//  Route and POI Mapper
//
//  Created by Dan Morgan on 10/10/25.
//

import SwiftUI
import Combine
import CoreLocation

struct RouteTrackingView: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var dataManager: DataManager
    
    @State private var showingSaveDialog = false
    @State private var routeName = ""
    @State private var showingFirstPointIndicator = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Status Display
            StatusCardView(locationManager: locationManager)
            
            // Tracking Controls
            TrackingControlsView(
                locationManager: locationManager,
                onSave: {
                    showingSaveDialog = true
                }
            )
            
            // Current Route Info
            if locationManager.isTracking {
                CurrentRouteInfoView(locationManager: locationManager)
            }
            
            Spacer()
        }
        .padding()
        .alert("Save Route", isPresented: $showingSaveDialog) {
            TextField("Route Name", text: $routeName)
            
            Button("Save") {
                saveRoute()
            }
            .disabled(routeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            
            Button("Cancel", role: .cancel) {
                routeName = ""
            }
        } message: {
            Text("Enter a name for this route")
        }
    }
    
    private func saveRoute() {
        let name = routeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = locationManager.exportCurrentRouteGeoJSON(named: name) {
            _ = dataManager.saveGeoJSONRouteFile(named: name, data: data)
        }
        locationManager.stopRouteTracking()
        routeName = ""
    }
}

struct StatusCardView: View {
    @ObservedObject var locationManager: LocationManager
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                    .font(.title2)
                
                Text(statusText)
                    .font(.headline)
                    .foregroundColor(statusColor)
                
                Spacer()
            }
            
            if let location = locationManager.location {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Latitude:")
                            .fontWeight(.medium)
                        Spacer()
                        Text(String(format: "%.6f", location.coordinate.latitude))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Longitude:")
                            .fontWeight(.medium)
                        Spacer()
                        Text(String(format: "%.6f", location.coordinate.longitude))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Altitude:")
                            .fontWeight(.medium)
                        Spacer()
                        Text(String(format: "%.1f m", location.altitude))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Accuracy:")
                            .fontWeight(.medium)
                        Spacer()
                        Text(String(format: "%.1f m", location.horizontalAccuracy))
                            .foregroundColor(location.horizontalAccuracy < 20 ? .green : .orange)
                    }
                }
            }
            
            if let errorMessage = locationManager.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            // Show first point acquisition status
            if locationManager.isTracking && locationManager.currentRoute.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Acquiring first point...")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            } else if locationManager.isTracking && !locationManager.currentRoute.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("First point recorded")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
    
    private var statusIcon: String {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return locationManager.isTracking ? "location.fill" : "location"
        case .denied, .restricted:
            return "location.slash"
        case .notDetermined:
            return "location.circle"
        @unknown default:
            return "location.circle"
        }
    }
    
    private var statusColor: Color {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return locationManager.isTracking ? .green : .blue
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }
    
    private var statusText: String {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return locationManager.isTracking ? "Tracking Route" : "Ready to Track"
        case .denied, .restricted:
            return "Location Access Denied"
        case .notDetermined:
            return "Location Permission Needed"
        @unknown default:
            return "Unknown Status"
        }
    }
}

struct TrackingControlsView: View {
    @ObservedObject var locationManager: LocationManager
    let onSave: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            if locationManager.authorizationStatus == .notDetermined {
                Button("Request Location Permission") {
                    locationManager.requestLocationPermission()
                }
                .buttonStyle(.glassProminent)
            } else if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
                Text("Location access is required to track routes. Please enable in Settings.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            } else {
                HStack(spacing: 20) {
                    if locationManager.isTracking {
                        if locationManager.isPaused {
                            Button("Resume") {
                                locationManager.resumeRouteTracking()
                            }
                            .buttonStyle(.glassProminent)
                            
                            Button("Stop Tracking") {
                                locationManager.stopRouteTracking()
                            }
                            .buttonStyle(.glass)
                            .foregroundColor(.red)
                        } else {
                            Button("Pause") {
                                locationManager.pauseRouteTracking()
                            }
                            .buttonStyle(.glass)
                            
                            Button("Stop Tracking") {
                                locationManager.stopRouteTracking()
                            }
                            .buttonStyle(.glass)
                            .foregroundColor(.red)
                            
                            Button("Save Route") {
                                onSave()
                            }
                            .buttonStyle(.glassProminent)
                            .disabled(locationManager.currentRoute.isEmpty)
                        }
                    } else {
                        Button(action: {
                            locationManager.startRouteTracking()
                        }) {
                            HStack {
                                if locationManager.isTracking && locationManager.currentRoute.isEmpty {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                }
                                Text(locationManager.isTracking && locationManager.currentRoute.isEmpty ? "Getting First Point..." : "Start Tracking")
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(locationManager.location == nil || (locationManager.isTracking && locationManager.currentRoute.isEmpty))
                    }
                }
            }
        }
    }
}

struct CurrentRouteInfoView: View {
    @ObservedObject var locationManager: LocationManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Route")
                .font(.headline)
            
            HStack {
                Text("Points Recorded:")
                Spacer()
                Text("\(locationManager.currentRoute.count)")
                    .fontWeight(.medium)
            }
            
            if let startTime = locationManager.routeStartTime {
                HStack {
                    Text("Started:")
                    Spacer()
                    Text(startTime.formatted(date: .omitted, time: .shortened))
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Duration:")
                    Spacer()
                    Text(formatDuration(from: startTime))
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 8))
    }
    
    private func formatDuration(from startTime: Date) -> String {
        let duration = Date().timeIntervalSince(startTime)
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

#Preview {
    RouteTrackingView(
        locationManager: LocationManager(),
        dataManager: DataManager()
    )
}
