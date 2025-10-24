//
//  SavedDataView.swift
//  Route and POI Mapper
//
//  Created by Dan Morgan on 10/10/25.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers
import CoreLocation

struct SavedDataView: View {
    @ObservedObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab = 0
    @State private var routeToShare: TrailRoute? = nil
    @State private var routeBeingEdited: TrailRoute? = nil
    @State private var editedRouteName: String = ""
    @State private var editedRouteColorName: String = "blue"
    
    // Add units system support
    @AppStorage("unitsSystem") private var unitsSystemRaw: String = "imperial"
    private var unitsSystem: UnitsSystem {
        UnitsSystem(rawValue: unitsSystemRaw) ?? .imperial
    }
    
    enum UnitsSystem: String, CaseIterable {
        case imperial = "imperial"
        case metric = "metric"
    }
    
    // Helper functions for unit conversions
    private func formatDistanceAndElevation(totalMeters: Double, totalAscentMeters: Double) -> (distance: Double, elevation: Double, distanceUnit: String, elevationUnit: String) {
        switch unitsSystem {
        case .imperial:
            let miles = totalMeters / 1609.344
            let feet = totalAscentMeters * 3.28084
            return (miles, feet, "miles", "feet")
        case .metric:
            let kilometers = totalMeters / 1000.0
            let meters = totalAscentMeters
            return (kilometers, meters, "km", "m")
        }
    }
    
    private func computeDistanceAndElevation(from segments: [[[Double]]]) -> (totalMeters: Double, totalAscentMeters: Double) {
        var totalMeters: Double = 0
        var totalAscentMeters: Double = 0
        for seg in segments {
            guard seg.count > 1 else { continue }
            for i in 1..<seg.count {
                let prev = seg[i - 1]
                let curr = seg[i]
                let p1 = CLLocation(latitude: prev[1], longitude: prev[0])
                let p2 = CLLocation(latitude: curr[1], longitude: curr[0])
                totalMeters += p1.distance(from: p2)
                if prev.count > 2 && curr.count > 2 {
                    let delta = curr[2] - prev[2]
                    if delta > 0 { totalAscentMeters += delta }
                }
            }
        }
        return (totalMeters, totalAscentMeters)
    }
    
    // State for the export format selection
    @State private var selectedRouteExportFormat = "geoJSON"
    @State private var selectedPOIExportFormat = "JSON"
    
    var body: some View {
        NavigationView {
            VStack {
                Picker("Data Type", selection: $selectedTab) {
                    Text("Routes").tag(0)
                    Text("POIs").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Export format selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Export Format")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.horizontal)
                    
                    if selectedTab == 0 {
                        // Routes export formats
                        Menu {
                            Button(action: {
                                selectedRouteExportFormat = "geoJSON"
                            }) {
                                HStack {
                                    Text("geoJSON")
                                    if selectedRouteExportFormat == "geoJSON" {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            
                            Button("GPX") {
                                selectedRouteExportFormat = "GPX"
                            }
                            .disabled(true)
                            
                            Button("KML") {
                                selectedRouteExportFormat = "KML"
                            }
                            .disabled(true)
                            
                            Button("TCX") {
                                selectedRouteExportFormat = "TCX"
                            }
                            .disabled(true)
                            
                            Button("FIT") {
                                selectedRouteExportFormat = "FIT"
                            }
                            .disabled(true)
                        } label: {
                            HStack {
                                Text(selectedRouteExportFormat)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)
                    } else {
                        // POIs export formats
                        Menu {
                            Button(action: {
                                selectedPOIExportFormat = "JSON"
                            }) {
                                HStack {
                                    Text("JSON")
                                    if selectedPOIExportFormat == "JSON" {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            
                            Button("CSV") {
                                selectedPOIExportFormat = "CSV"
                            }
                            .disabled(true)
                            
                            Button("KML") {
                                selectedPOIExportFormat = "KML"
                            }
                            .disabled(true)
                            
                            Button("geoJSON") {
                                selectedPOIExportFormat = "geoJSON"
                            }
                            .disabled(true)
                            
                            Button("Shapefile") {
                                selectedPOIExportFormat = "Shapefile"
                            }
                            .disabled(true)
                        } label: {
                            HStack {
                                Text(selectedPOIExportFormat)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        .onAppear {
                            // Ensure the initial value is properly set on first load
                            print("[POI Menu] onAppear - current selectedPOIExportFormat: '\(selectedPOIExportFormat)'")
                            if selectedPOIExportFormat.isEmpty {
                                selectedPOIExportFormat = "JSON"
                                print("[POI Menu] Set selectedPOIExportFormat to JSON")
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                
                if selectedTab == 0 {
                    RoutesListView(
                        dataManager: dataManager,
                        selectedExportFormat: selectedRouteExportFormat,
                        onExportFile: { route in
                            routeToShare = route
                        },
                        onTap: { route in
                            editedRouteName = route.name
                            editedRouteColorName = dataManagerColorName(for: route).lowercased()
                            routeBeingEdited = route
                        }
                    )
                } else {
                    POIsListView(dataManager: dataManager, selectedExportFormat: selectedPOIExportFormat)
                        .id(dataManager.savedPOIs.count)
                }
            }
            .navigationTitle("Saved Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                }
            }
            .sheet(item: $routeToShare) { route in
                NavigationView {
                    RouteExportShareView(route: route, unitsSystem: unitsSystem, exportFormat: selectedRouteExportFormat)
                        .navigationTitle("Export Route")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    routeToShare = nil
                                }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $routeBeingEdited) { route in
                RouteEditModal(route: route, name: $editedRouteName, colorName: $editedRouteColorName) { newName, newColorName in
                    updateRoute(route, newName: newName, newColorName: newColorName)
                }
            }
            .onAppear {
                // Debug: Ensure POI export format is set on initial load
                print("[SavedDataView] onAppear - selectedPOIExportFormat: '\(selectedPOIExportFormat)'")
                if selectedPOIExportFormat.isEmpty {
                    selectedPOIExportFormat = "JSON"
                    print("[SavedDataView] Initialized selectedPOIExportFormat to JSON")
                }
            }
        }
    }
}

struct RoutesListView: View {
    @ObservedObject var dataManager: DataManager
    let selectedExportFormat: String
    let onExportFile: (TrailRoute) -> Void
    let onTap: (TrailRoute) -> Void
    
    var body: some View {
        List {
            if dataManager.savedRoutes.isEmpty {
                Text("No saved routes")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(dataManager.savedRoutes) { route in
                    RouteRowView(
                        route: route,
                        selectedExportFormat: selectedExportFormat,
                        onExportFile: { r in
                            onExportFile(r)
                        },
                        onTap: { r in
                            onTap(r)
                        }
                    )
                }
                .onDelete(perform: deleteRoutes)
            }
        }
    }
    
    private func deleteRoutes(offsets: IndexSet) {
        for index in offsets {
            dataManager.deleteRoute(dataManager.savedRoutes[index])
        }
    }
}

struct RouteRowView: View {
    let route: TrailRoute
    let selectedExportFormat: String
    let onExportFile: (TrailRoute) -> Void
    let onTap: (TrailRoute) -> Void
    
    private var formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
    
    private func routeColorName() -> String {
        route.colorName ?? "blue"
    }
    
    private func routeColor() -> Color {
        let name = routeColorName().lowercased()
        switch name {
        case "black": return .black
        case "blue": return .blue
        case "brown": return .brown
        case "cyan": return .cyan
        case "gray": return .gray
        case "green": return .green
        case "indigo": return .indigo
        case "mint": return .mint
        case "orange": return .orange
        case "pink": return .pink
        case "purple": return .purple
        case "red": return .red
        case "teal": return .teal
        case "white": return .white
        case "yellow": return .yellow
        default: return .blue
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(routeColor())
                    .frame(width: 10, height: 10)
                Text(route.name)
                    .font(.headline)
            }
            
            Text("Started: \(formatter.string(from: route.startTime))")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let endTime = route.endTime {
                Text("Ended: \(formatter.string(from: endTime))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("\(route.coordinates.count) points")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { onTap(route) }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                // Check if the selected format is supported
                let normalizedFormat = selectedExportFormat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if normalizedFormat == "geojson" {
                    onExportFile(route)
                } else {
                    // For now, show an alert or just proceed with geoJSON as fallback
                    // In the future, this will support other formats
                    print("[Route Export] Format '\(selectedExportFormat)' not yet supported, using geoJSON")
                    onExportFile(route)
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }.tint(.blue)
        }
    }
}

struct POIShareData: Identifiable {
    let id = UUID()
    let url: URL
}

struct POIsListView: View {
    @ObservedObject var dataManager: DataManager
    let selectedExportFormat: String
    
    @State private var showClearConfirm = false
    @State private var saveResultMessage: String? = nil
    @State private var showSaveResultAlert = false
    
    @State private var poiShareData: POIShareData? = nil
    
    var body: some View {
        VStack {
            List {
                if dataManager.savedPOIs.isEmpty {
                    Text("No saved POIs")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(dataManager.savedPOIs) { poi in
                        POIRowView(poi: poi)
                    }
                    .onDelete(perform: deletePOIs)
                }
            }
            .listStyle(.insetGrouped)

            // Action buttons outside the List
            HStack(spacing: 12) {
                Button(action: { showClearConfirm = true }) {
                    Text("Clear History")
                        .font(.headline)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                }
                .background(Color.red.opacity(0.12))
                .foregroundColor(.red)
                .clipShape(Capsule())
                
                Button(action: {
                    print("[Export] Export Data tapped")
                    print("[Export] Selected format: '\(selectedExportFormat)' (length: \(selectedExportFormat.count))")
                    print("[Export] Number of POIs to export: \(dataManager.savedPOIs.count)")
                    
                    if dataManager.savedPOIs.isEmpty {
                        saveResultMessage = "No POIs to export. Add some POIs first."
                        showSaveResultAlert = true
                        return
                    }
                    
                    // For now, only JSON is supported - normalize the format string for comparison
                    let normalizedFormat = selectedExportFormat.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    print("[Export] Normalized format: '\(normalizedFormat)'")
                    
                    if normalizedFormat == "JSON" {
                        print("[Export] Format check passed, calling exportPOIsAsCustomJSONFile()")
                        if let url = dataManager.exportPOIsAsCustomJSONFile() {
                            print("[Export] Generated file URL: \(url.absoluteString)")
                            print("[Export] File exists: \(FileManager.default.fileExists(atPath: url.path))")
                            
                            // Create share data and trigger sheet
                            poiShareData = POIShareData(url: url)
                            print("[Export] Set poiShareData with URL: \(url.absoluteString)")
                        } else {
                            print("[Export] exportPOIsAsCustomJSONFile() returned nil")
                            saveResultMessage = "Failed to generate export file. Check console for details."
                            showSaveResultAlert = true
                        }
                    } else {
                        print("[Export] Format check failed: '\(normalizedFormat)' is not 'JSON'")
                        saveResultMessage = "Export format '\(selectedExportFormat)' is not yet supported. Only JSON export is currently available."
                        showSaveResultAlert = true
                    }
                }) {
                    Text("Export Data")
                        .font(.headline)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                }
                .background(Color.blue.opacity(0.12))
                .foregroundColor(.blue)
                .clipShape(Capsule())
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .confirmationDialog("Clear all saved POIs?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) {
                dataManager.clearAllPOIs()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all saved POIs from the device.")
        }
        .alert(saveResultMessage ?? "", isPresented: $showSaveResultAlert) {
            Button("OK", role: .cancel) {}
        }
        .sheet(item: $poiShareData) { shareData in
            NavigationView {
                VStack(spacing: 20) {
                    let _ = print("[Sheet] Sheet presented with shareData URL: \(shareData.url.absoluteString)")
                    
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                    
                    Text("POIs Ready to Share")
                        .font(.title2)
                        .bold()
                    
                    Text(shareData.url.lastPathComponent)
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    ShareLink(item: shareData.url) {
                        Label("Share POIs", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                }
                .padding()
                .navigationTitle("Share POIs")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            print("[Sheet] Done button tapped, closing sheet")
                            poiShareData = nil
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
    
    private func deletePOIs(offsets: IndexSet) {
        for index in offsets {
            dataManager.deletePOI(dataManager.savedPOIs[index])
        }
    }
}

struct POIRowView: View {
    let poi: PointOfInterest
    
    private var formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
    
    var body: some View {
        HStack {
            Image(systemName: "mappin.circle.fill")
                .foregroundColor(.blue)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(poi.name)
                    .font(.headline)
                Text(poi.category)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct ShareContentView: View {
    let fileURL: URL?
    let content: String?
    
    init(fileURL: URL) {
        self.fileURL = fileURL
        self.content = nil
    }
    
    init(content: String) {
        self.fileURL = nil
        self.content = content
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 50))
                .foregroundColor(.blue)
            
            if let fileURL = fileURL {
                Text("Ready to Share")
                    .font(.title2)
                    .bold()
                
                Text(fileURL.lastPathComponent)
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                ShareLink(item: fileURL) {
                    Label("Share File", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                
            } else if let content = content {
                Text("Ready to Share")
                    .font(.title2)
                    .bold()
                
                Text("Text Content")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                ShareLink(item: content) {
                    Label("Share Text", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
            }
        }
        .padding()
    }
}

/*
 * RouteExportShareView - Handles route export in multiple formats
 * 
 * Currently supported formats:
 * - geoJSON: Fully implemented using route.exportGeoJSON()
 * 
 * Formats ready for implementation:
 * - GPX: GPS Exchange Format - needs implementation
 * - KML: Keyhole Markup Language - needs implementation  
 * - TCX: Training Center XML - needs implementation
 * - FIT: Flexible and Interoperable Data Transfer - needs implementation
 *
 * To add a new format:
 * 1. Add case to prepareRouteExportFile() switch statement
 * 2. Create prepare[Format]Export() method following prepareGeoJSONExport() pattern
 * 3. Implement format-specific generation logic
 * 4. Set appropriate file extension and MIME type
 */
struct RouteExportShareView: View {
    let route: TrailRoute
    let unitsSystem: SavedDataView.UnitsSystem
    let exportFormat: String

    @State private var exportURL: URL? = nil
    @State private var exportError: String? = nil
    
    var body: some View {
        VStack(spacing: 20) {
            if let url = exportURL {
                Image(systemName: "map")
                    .font(.system(size: 50))
                    .foregroundColor(.blue)
                
                Text("Route Ready to Share")
                    .font(.title2)
                    .bold()
                
                Text(url.lastPathComponent)
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                ShareLink(item: url) {
                    Label("Share Route", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                
            } else if let error = exportError {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 50))
                    .foregroundColor(.orange)
                
                Text("Export Failed")
                    .font(.title2)
                    .bold()
                
                Text(error)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                    .padding()
                
                Text("Preparing export…")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .onAppear {
            prepareRouteExportFile()
        }
    }
    
    private func prepareRouteExportFile() {
        let normalizedFormat = exportFormat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        switch normalizedFormat {
        case "geojson":
            prepareGeoJSONExport()
        case "gpx":
            exportError = "GPX export is not yet implemented. Please use geoJSON format."
        case "kml":
            exportError = "KML export is not yet implemented. Please use geoJSON format."
        case "tcx":
            exportError = "TCX export is not yet implemented. Please use geoJSON format."
        case "fit":
            exportError = "FIT export is not yet implemented. Please use geoJSON format."
        default:
            exportError = "Unsupported export format '\(exportFormat)'. Please use geoJSON format."
        }
    }
    
    private func prepareGeoJSONExport() {
        // Build segments and compute info string
        let segments: [[[Double]]] = route.segments ?? [route.coordinates.map { [ $0.longitude, $0.latitude, $0.altitude ] }]
        let (totalMeters, totalAscentMeters) = computeDistanceAndElevation(from: segments)
        let (distance, elevation, distanceUnit, elevationUnit) = formatDistanceAndElevation(totalMeters: totalMeters, totalAscentMeters: totalAscentMeters)
        
        let infoString = String(format: "Length: %.2f %@. Elevation gain: %.0f %@.", distance, distanceUnit, elevation, elevationUnit)
        let collection = route.exportGeoJSON(info: infoString)

        // Serialize to JSON data
        guard let data = try? JSONSerialization.data(withJSONObject: collection, options: .prettyPrinted) else {
            exportError = "Failed to prepare geoJSON export."
            return
        }

        // Determine filename using the GeoJSON "name" value if present; otherwise fall back to route.name
        let geoName: String = {
            if let features = collection["features"] as? [[String: Any]],
               let first = features.first,
               let properties = first["properties"] as? [String: Any],
               let name = properties["name"] as? String,
               !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return name
            }
            return route.name
        }()

        // Build a sanitized filename with a timestamp and .geojson extension
        let timestamp = DateFormatter.exportTimestamp.string(from: Date())
        let base = sanitizedFilename(from: geoName)
        let filename = "\(base)-\(timestamp).geojson"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: tempURL, options: [.atomic])
            exportURL = tempURL
        } catch {
            exportError = "Failed to write temporary file: \(error.localizedDescription)"
        }
    }

    // Helper functions for unit conversions
    private func formatDistanceAndElevation(totalMeters: Double, totalAscentMeters: Double) -> (distance: Double, elevation: Double, distanceUnit: String, elevationUnit: String) {
        switch unitsSystem {
        case .imperial:
            let miles = totalMeters / 1609.344
            let feet = totalAscentMeters * 3.28084
            return (miles, feet, "miles", "feet")
        case .metric:
            let kilometers = totalMeters / 1000.0
            let meters = totalAscentMeters
            return (kilometers, meters, "km", "m")
        }
    }
    
    private func computeDistanceAndElevation(from segments: [[[Double]]]) -> (totalMeters: Double, totalAscentMeters: Double) {
        var totalMeters: Double = 0
        var totalAscentMeters: Double = 0
        for seg in segments {
            guard seg.count > 1 else { continue }
            for i in 1..<seg.count {
                let prev = seg[i - 1]
                let curr = seg[i]
                let p1 = CLLocation(latitude: prev[1], longitude: prev[0])
                let p2 = CLLocation(latitude: curr[1], longitude: curr[0])
                totalMeters += p1.distance(from: p2)
                if prev.count > 2 && curr.count > 2 {
                    let delta = curr[2] - prev[2]
                    if delta > 0 { totalAscentMeters += delta }
                }
            }
        }
        return (totalMeters, totalAscentMeters)
    }

    // Helper to sanitize a base filename (without extension)
    private func sanitizedFilename(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let replaced = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "?", with: "-")
            .replacingOccurrences(of: "*", with: "-")
            .replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "<", with: "(")
            .replacingOccurrences(of: ">", with: ")")
            .replacingOccurrences(of: "|", with: "-")
        let collapsed = replaced
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return collapsed.isEmpty ? "Export" : collapsed
    }
}

fileprivate extension DateFormatter {
    static let exportTimestamp: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()
}

extension SavedDataView {
    private func colorOptions() -> [String] {
        ["black","blue","brown","cyan","gray","green","indigo","mint","orange","pink","purple","red","teal","white","yellow"]
    }
    
    private func swiftUIColor(for name: String) -> Color {
        switch name.lowercased() {
        case "black": return .black
        case "blue": return .blue
        case "brown": return .brown
        case "cyan": return .cyan
        case "gray": return .gray
        case "green": return .green
        case "indigo": return .indigo
        case "mint": return .mint
        case "orange": return .orange
        case "pink": return .pink
        case "purple": return .purple
        case "red": return .red
        case "teal": return .teal
        case "white": return .white
        case "yellow": return .yellow
        default: return .blue
        }
    }
    
    private func dataManagerColorName(for route: TrailRoute) -> String {
        (route.colorName ?? "blue").lowercased()
    }
    
    private func storeColorName(_ name: String, for route: TrailRoute) {
        let updated = TrailRoute(id: route.id, name: route.name, startTime: route.startTime, endTime: route.endTime, coordinates: route.coordinates, segments: route.segments, colorName: name)
        dataManager.updateRoute(updated)
    }
    
    private func updateRoute(_ route: TrailRoute, newName: String, newColorName: String) {
        let normalizedColorName = newColorName.lowercased()
        let updatedRoute = TrailRoute(id: route.id, name: newName, startTime: route.startTime, endTime: route.endTime, coordinates: route.coordinates, segments: route.segments, colorName: normalizedColorName)
        dataManager.updateRoute(updatedRoute)
    }
}

struct RouteEditModal: View {
    let route: TrailRoute
    @Binding var name: String
    @Binding var colorName: String
    let onSave: (String, String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Route Name") {
                    TextField("Enter a name", text: $name)
                }
                Section("Color") {
                    Picker("Color", selection: $colorName) {
                        ForEach(colorOptions(), id: \.self) { n in
                            HStack {
                                Circle()
                                    .fill(swiftUIColor(for: n))
                                    .frame(width: 16, height: 16)
                                Text(n.capitalized)
                            }
                            .tag(n)
                        }
                    }
                    .pickerStyle(.wheel)
                }
            }
            .navigationTitle("Edit Route")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmedName, colorName)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func colorOptions() -> [String] {
        ["black","blue","brown","cyan","gray","green","indigo","mint","orange","pink","purple","red","teal","white","yellow"]
    }
    
    private func swiftUIColor(for name: String) -> Color {
        switch name.lowercased() {
        case "black": return .black
        case "blue": return .blue
        case "brown": return .brown
        case "cyan": return .cyan
        case "gray": return .gray
        case "green": return .green
        case "indigo": return .indigo
        case "mint": return .mint
        case "orange": return .orange
        case "pink": return .pink
        case "purple": return .purple
        case "red": return .red
        case "teal": return .teal
        case "white": return .white
        case "yellow": return .yellow
        default: return .blue
        }
    }
}

#Preview {
    SavedDataView(dataManager: DataManager())
}

