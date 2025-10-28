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
    
    @State private var poiBeingEdited: PointOfInterest? = nil
    @State private var editedPOIName: String = ""
    @State private var editedPOIColorName: String = "blue"
    @State private var editedPOICategory: String = ""
    
    // Add units system support
    @AppStorage("unitsSystem") private var unitsSystemRaw: String = "imperial"
    private var unitsSystem: UnitsSystem {
        UnitsSystem(rawValue: unitsSystemRaw) ?? .imperial
    }
    
    // Add elevation smoothing support
    @AppStorage("elevationSmoothingEnabled") private var elevationSmoothingEnabled: Bool = true
    @AppStorage("elevationSmoothingWindow") private var elevationSmoothingWindow: Int = 7
    @AppStorage("elevationGainThresholdMeters") private var elevationGainThresholdMeters: Double = 0.5
    
    enum UnitsSystem: String, CaseIterable {
        case imperial = "imperial"
        case metric = "metric"
    }
    
    // Elevation smoothing function (copied from MapView.swift)
    private func smoothElevations(_ elevs: [Double], window: Int) -> [Double] {
        let w = max(1, window)
        guard w > 1, elevs.count >= w else { return elevs }
        var out = elevs
        let k = w / 2
        for i in k..<(elevs.count - k) {
            let slice = elevs[(i - k)...(i + k)]
            out[i] = slice.reduce(0, +) / Double(slice.count)
        }
        return out
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
            
            // Extract elevations with fallback to 0.0
            let elevations = seg.map { $0.count > 2 ? $0[2] : 0.0 }
            var processedElevations = elevations
            
            // Apply elevation smoothing if enabled and we have enough points
            if elevationSmoothingEnabled && elevationSmoothingWindow >= 3 && elevations.count >= elevationSmoothingWindow {
                let window = elevationSmoothingWindow % 2 == 1 ? elevationSmoothingWindow : elevationSmoothingWindow + 1
                processedElevations = smoothElevations(elevations, window: window)
            }
            
            // Calculate distance and elevation gain
            for i in 1..<seg.count {
                let prev = seg[i - 1]
                let curr = seg[i]
                let p1 = CLLocation(latitude: prev[1], longitude: prev[0])
                let p2 = CLLocation(latitude: curr[1], longitude: curr[0])
                totalMeters += p1.distance(from: p2)
                
                // Calculate elevation gain based on smoothing setting
                if elevationSmoothingEnabled {
                    // When ON: Use smoothed elevations with threshold
                    let deltaElev = processedElevations[i] - processedElevations[i - 1]
                    if deltaElev > elevationGainThresholdMeters {
                        totalAscentMeters += deltaElev
                    }
                } else {
                    // When OFF: Use raw elevations, count all positive changes
                    let deltaElev = elevations[i] - elevations[i - 1]
                    if deltaElev > 0 {
                        totalAscentMeters += deltaElev
                    }
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
                            
                            Button("KML") {
                                selectedRouteExportFormat = "KML"
                            }
                            
                            Button("TCX") {
                                selectedRouteExportFormat = "TCX"
                            }
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
                            ForEach(POIExportManager.availableFormats, id: \.name) { format in
                                Button(action: {
                                    selectedPOIExportFormat = format.name
                                }) {
                                    HStack {
                                        Text(format.name)
                                        if selectedPOIExportFormat == format.name {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                            }
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
                    POIsListView(
                        dataManager: dataManager,
                        selectedExportFormat: selectedPOIExportFormat,
                        onTap: { poi in
                            editedPOIName = poi.name
                            editedPOIColorName = (poi.colorName ?? "blue").lowercased()
                            editedPOICategory = poi.category
                            poiBeingEdited = poi
                        }
                    )
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
            .sheet(item: $poiBeingEdited) { poi in
                POIEditModal(
                    poi: poi,
                    name: $editedPOIName,
                    colorName: $editedPOIColorName,
                    category: $editedPOICategory,
                    dataManager: dataManager
                ) { newName, newColorName, newCategory in
                    updatePOI(poi, newName: newName, newColorName: newColorName, newCategory: newCategory)
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
                onExportFile(route)
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
    let onTap: (PointOfInterest) -> Void
    
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
                        POIRowView(poi: poi, onTap: onTap)
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
                    
                    // Use POIExportManager to handle the export
                    guard let exportFormat = POIExportManager.format(named: selectedExportFormat) else {
                        print("[Export] Unknown format: '\(selectedExportFormat)'")
                        saveResultMessage = "Export format '\(selectedExportFormat)' is not supported."
                        showSaveResultAlert = true
                        return
                    }
                    
                    let exportManager = POIExportManager()
                    
                    do {
                        print("[Export] Attempting to export using \(exportFormat.name) format")
                        let url = try exportManager.exportPOIs(dataManager.savedPOIs, format: exportFormat)
                        print("[Export] Generated file URL: \(url.absoluteString)")
                        print("[Export] File exists: \(FileManager.default.fileExists(atPath: url.path))")
                        
                        // Create share data and trigger sheet
                        poiShareData = POIShareData(url: url)
                        print("[Export] Set poiShareData with URL: \(url.absoluteString)")
                    } catch {
                        print("[Export] Export failed: \(error.localizedDescription)")
                        saveResultMessage = "Export failed: \(error.localizedDescription)"
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
    let onTap: (PointOfInterest) -> Void
    
    private var formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
    
    private func poiColorName() -> String {
        poi.colorName ?? "blue"
    }
    
    private func poiColor() -> Color {
        let name = poiColorName().lowercased()
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
        HStack {
            Image(systemName: "mappin.circle.fill")
                .foregroundColor(poiColor())
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
        .contentShape(Rectangle())
        .onTapGesture { onTap(poi) }
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
 * - GPX: Fully implemented using custom GPX generation
 * - KML: Fully implemented using custom KML generation
 * - TCX: Fully implemented using custom TCX generation
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
    
    // Add elevation smoothing support
    @AppStorage("elevationSmoothingEnabled") private var elevationSmoothingEnabled: Bool = true
    @AppStorage("elevationSmoothingWindow") private var elevationSmoothingWindow: Int = 7
    @AppStorage("elevationGainThresholdMeters") private var elevationGainThresholdMeters: Double = 0.5
    
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
            prepareGPXExport()
        case "kml":
            prepareKMLExport()
        case "tcx":
            prepareTCXExport()
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
    
    private func prepareGPXExport() {
        // Generate GPX content
        let gpxContent = generateGPXContent()
        
        // Convert to data
        guard let data = gpxContent.data(using: .utf8) else {
            exportError = "Failed to prepare GPX export."
            return
        }
        
        // Generate filename with timestamp and .gpx extension
        let timestamp = DateFormatter.exportTimestamp.string(from: Date())
        let base = sanitizedFilename(from: route.name)
        let filename = "\(base)-\(timestamp).gpx"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        do {
            try data.write(to: tempURL, options: [.atomic])
            exportURL = tempURL
        } catch {
            exportError = "Failed to write temporary file: \(error.localizedDescription)"
        }
    }
    
    private func generateGPXContent() -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Calculate track statistics
        let segments: [[[Double]]] = route.segments ?? [route.coordinates.map { [$0.longitude, $0.latitude, $0.altitude] }]
        let (totalMeters, totalAscentMeters) = computeDistanceAndElevation(from: segments)
        let (distance, elevation, distanceUnit, elevationUnit) = formatDistanceAndElevation(totalMeters: totalMeters, totalAscentMeters: totalAscentMeters)
        
        var gpxContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Gretel for iOS, developed by Dan Morgan Designs" xmlns="http://www.topografix.com/GPX/1/1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
          <metadata>
            <name>\(xmlEscape(route.name))</name>
            <desc>Length: \(String(format: "%.2f", distance)) \(distanceUnit). Elevation gain: \(String(format: "%.0f", elevation)) \(elevationUnit).</desc>
            <time>\(dateFormatter.string(from: route.startTime))</time>
          </metadata>
          <trk>
            <name>\(xmlEscape(route.name))</name>
            <desc>Track recorded by Gretel for iOS, developed by Dan Morgan Designs</desc>
        
        """
        
        // Add track segments
        for (segmentIndex, segment) in segments.enumerated() {
            gpxContent += "    <trkseg>\n"
            
            for (pointIndex, point) in segment.enumerated() {
                guard point.count >= 2 else { continue }
                
                let longitude = point[0]
                let latitude = point[1]
                let elevation = point.count > 2 ? point[2] : 0.0
                
                // Try to get timestamp from coordinates array if available
                let timestamp: String
                if pointIndex < route.coordinates.count {
                    timestamp = dateFormatter.string(from: route.coordinates[pointIndex].timestamp)
                } else {
                    // Interpolate timestamp based on position and total duration
                    let totalPoints = segments.flatMap { $0 }.count
                    let currentPointIndex = segments.prefix(segmentIndex).flatMap { $0 }.count + pointIndex
                    let progress = Double(currentPointIndex) / Double(max(totalPoints - 1, 1))
                    
                    let startTime = route.startTime.timeIntervalSince1970
                    let endTime = route.endTime?.timeIntervalSince1970 ?? startTime
                    let interpolatedTime = startTime + (endTime - startTime) * progress
                    
                    timestamp = dateFormatter.string(from: Date(timeIntervalSince1970: interpolatedTime))
                }
                
                gpxContent += "      <trkpt lat=\"\(latitude)\" lon=\"\(longitude)\">\n"
                if elevation > 0 {
                    gpxContent += "        <ele>\(elevation)</ele>\n"
                }
                gpxContent += "        <time>\(timestamp)</time>\n"
                gpxContent += "      </trkpt>\n"
            }
            
            gpxContent += "    </trkseg>\n"
        }
        
        gpxContent += """
          </trk>
        </gpx>
        """
        
        return gpxContent
    }
    
    // XML escaping helper function
    private func xmlEscape(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    
    private func prepareKMLExport() {
        // Generate KML content
        let kmlContent = generateKMLContent()
        
        // Convert to data
        guard let data = kmlContent.data(using: .utf8) else {
            exportError = "Failed to prepare KML export."
            return
        }
        
        // Generate filename with timestamp and .kml extension
        let timestamp = DateFormatter.exportTimestamp.string(from: Date())
        let base = sanitizedFilename(from: route.name)
        let filename = "\(base)-\(timestamp).kml"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        do {
            try data.write(to: tempURL, options: [.atomic])
            exportURL = tempURL
        } catch {
            exportError = "Failed to write temporary file: \(error.localizedDescription)"
        }
    }
    
    private func generateKMLContent() -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        
        // Calculate track statistics
        let segments: [[[Double]]] = route.segments ?? [route.coordinates.map { [$0.longitude, $0.latitude, $0.altitude] }]
        let (totalMeters, totalAscentMeters) = computeDistanceAndElevation(from: segments)
        let (distance, elevation, distanceUnit, elevationUnit) = formatDistanceAndElevation(totalMeters: totalMeters, totalAscentMeters: totalAscentMeters)
        
        // Convert route color to KML color format (AABBGGRR in hex)
        let kmlColor = convertRouteColorToKML()
        
        var kmlContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
          <Document>
            <name>\(xmlEscape(route.name))</name>
            <description><![CDATA[
              <p><strong>Route Statistics:</strong></p>
              <ul>
                <li>Length: \(String(format: "%.2f", distance)) \(distanceUnit)</li>
                <li>Elevation Gain: \(String(format: "%.0f", elevation)) \(elevationUnit)</li>
                <li>Start Time: \(dateFormatter.string(from: route.startTime))</li>
        """
        
        if let endTime = route.endTime {
            kmlContent += """
                    <li>End Time: \(dateFormatter.string(from: endTime))</li>
            """
        }
        
        kmlContent += """
              </ul>
              <p>Generated by Gretel for iOS, developed by Dan Morgan Designs</p>
            ]]></description>
            
            <Style id="routeStyle">
              <LineStyle>
                <color>\(kmlColor)</color>
                <width>4</width>
              </LineStyle>
            </Style>
            
            <Placemark>
              <name>\(xmlEscape(route.name))</name>
              <description>Track recorded by Gretel for iOS, developed by Dan Morgan Designs</description>
              <styleUrl>#routeStyle</styleUrl>
        """
        
        // Determine if we have multiple segments
        if segments.count > 1 {
            // Use MultiGeometry for multiple segments
            kmlContent += "      <MultiGeometry>\n"
            
            for segment in segments {
                kmlContent += generateKMLLineString(from: segment)
            }
            
            kmlContent += "      </MultiGeometry>\n"
        } else {
            // Use single LineString for single segment
            if let firstSegment = segments.first {
                kmlContent += generateKMLLineString(from: firstSegment)
            }
        }
        
        kmlContent += """
            </Placemark>
          </Document>
        </kml>
        """
        
        return kmlContent
    }
    
    private func generateKMLLineString(from segment: [[Double]]) -> String {
        var lineString = """
              <LineString>
                <tessellate>1</tessellate>
                <altitudeMode>clampToGround</altitudeMode>
                <coordinates>
        """
        
        for point in segment {
            guard point.count >= 2 else { continue }
            
            let longitude = point[0]
            let latitude = point[1]
            
            // KML coordinates format: longitude,latitude (no altitude for simplified version)
            lineString += "\(longitude),\(latitude) "
        }
        
        lineString += """
                </coordinates>
              </LineString>
        """
        
        return lineString
    }
    
    private func convertRouteColorToKML() -> String {
        // KML uses AABBGGRR format (Alpha, Blue, Green, Red) in hexadecimal
        // Default to semi-transparent blue if no color is specified
        let colorName = route.colorName?.lowercased() ?? "blue"
        
        switch colorName {
        case "black": return "ff000000"     // Black
        case "blue": return "ffff0000"      // Blue  
        case "brown": return "ff2f4f4f"     // Brown (approximation)
        case "cyan": return "ffffff00"      // Cyan
        case "gray": return "ff808080"      // Gray
        case "green": return "ff00ff00"     // Green
        case "indigo": return "ff82004b"    // Indigo (approximation)
        case "mint": return "ff00ffaa"      // Mint (approximation)
        case "orange": return "ff0080ff"    // Orange
        case "pink": return "ffcbc0ff"      // Pink
        case "purple": return "ff800080"    // Purple
        case "red": return "ff0000ff"       // Red
        case "teal": return "ff808000"      // Teal
        case "white": return "ffffffff"     // White
        case "yellow": return "ff00ffff"    // Yellow
        default: return "ffff0000"          // Default to blue
        }
    }
    
    private func prepareTCXExport() {
        // Generate TCX content
        let tcxContent = generateTCXContent()
        
        // Convert to data
        guard let data = tcxContent.data(using: .utf8) else {
            exportError = "Failed to prepare TCX export."
            return
        }
        
        // Generate filename with timestamp and .tcx extension
        let timestamp = DateFormatter.exportTimestamp.string(from: Date())
        let base = sanitizedFilename(from: route.name)
        let filename = "\(base)-\(timestamp).tcx"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        do {
            try data.write(to: tempURL, options: [.atomic])
            exportURL = tempURL
        } catch {
            exportError = "Failed to write temporary file: \(error.localizedDescription)"
        }
    }
    
    private func generateTCXContent() -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Calculate track statistics
        let segments: [[[Double]]] = route.segments ?? [route.coordinates.map { [$0.longitude, $0.latitude, $0.altitude] }]
        let (totalMeters, totalAscentMeters) = computeDistanceAndElevation(from: segments)
        let (distance, elevation, distanceUnit, elevationUnit) = formatDistanceAndElevation(totalMeters: totalMeters, totalAscentMeters: totalAscentMeters)
        
        // Calculate total duration
        let totalTime = route.endTime?.timeIntervalSince(route.startTime) ?? 0
        
        var tcxContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <TrainingCenterDatabase xsi:schemaLocation="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2 http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd" xmlns:ns5="http://www.garmin.com/xmlschemas/ActivityGoals/v1" xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2" xmlns:ns2="http://www.garmin.com/xmlschemas/UserProfile/v2" xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:ns4="http://www.garmin.com/xmlschemas/ProfileExtension/v1">
          <Activities>
            <Activity Sport="Other">
              <Id>\(dateFormatter.string(from: route.startTime))</Id>
              <Notes>\(xmlEscape(route.name)) - Track recorded by Gretel for iOS, developed by Dan Morgan Designs</Notes>
              <Lap StartTime="\(dateFormatter.string(from: route.startTime))">
                <TotalTimeSeconds>\(totalTime)</TotalTimeSeconds>
                <DistanceMeters>\(totalMeters)</DistanceMeters>
                <Calories>0</Calories>
                <Intensity>Active</Intensity>
                <TriggerMethod>Manual</TriggerMethod>
                <Track>
        
        """
        
        // Add track points from all segments
        let allPoints = segments.flatMap { $0 }
        
        for (pointIndex, point) in allPoints.enumerated() {
            guard point.count >= 2 else { continue }
            
            let longitude = point[0]
            let latitude = point[1]
            let elevation = point.count > 2 ? point[2] : 0.0
            
            // Try to get timestamp from coordinates array if available
            let timestamp: String
            if pointIndex < route.coordinates.count {
                timestamp = dateFormatter.string(from: route.coordinates[pointIndex].timestamp)
            } else {
                // Interpolate timestamp based on position and total duration
                let totalPoints = allPoints.count
                let progress = Double(pointIndex) / Double(max(totalPoints - 1, 1))
                
                let startTime = route.startTime.timeIntervalSince1970
                let endTime = route.endTime?.timeIntervalSince1970 ?? startTime
                let interpolatedTime = startTime + (endTime - startTime) * progress
                
                timestamp = dateFormatter.string(from: Date(timeIntervalSince1970: interpolatedTime))
            }
            
            // Calculate distance from start (cumulative)
            var distanceFromStart: Double = 0
            if pointIndex > 0 {
                for i in 1...pointIndex {
                    let prev = allPoints[i - 1]
                    let curr = allPoints[i]
                    let p1 = CLLocation(latitude: prev[1], longitude: prev[0])
                    let p2 = CLLocation(latitude: curr[1], longitude: curr[0])
                    distanceFromStart += p1.distance(from: p2)
                }
            }
            
            tcxContent += """
                  <Trackpoint>
                    <Time>\(timestamp)</Time>
                    <Position>
                      <LatitudeDegrees>\(latitude)</LatitudeDegrees>
                      <LongitudeDegrees>\(longitude)</LongitudeDegrees>
                    </Position>
                    <AltitudeMeters>\(elevation)</AltitudeMeters>
                    <DistanceMeters>\(distanceFromStart)</DistanceMeters>
                  </Trackpoint>
            
            """
        }
        
        tcxContent += """
                </Track>
              </Lap>
            </Activity>
          </Activities>
          <Author xsi:type="Application_t">
            <Name>Gretel for iOS, developed by Dan Morgan Designs</Name>
          </Author>
        </TrainingCenterDatabase>
        """
        
        return tcxContent
    }
    



    // Elevation smoothing function (copied from MapView.swift)
    private func smoothElevations(_ elevs: [Double], window: Int) -> [Double] {
        let w = max(1, window)
        guard w > 1, elevs.count >= w else { return elevs }
        var out = elevs
        let k = w / 2
        for i in k..<(elevs.count - k) {
            let slice = elevs[(i - k)...(i + k)]
            out[i] = slice.reduce(0, +) / Double(slice.count)
        }
        return out
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
            
            // Extract elevations with fallback to 0.0
            let elevations = seg.map { $0.count > 2 ? $0[2] : 0.0 }
            var processedElevations = elevations
            
            // Apply elevation smoothing if enabled and we have enough points
            if elevationSmoothingEnabled && elevationSmoothingWindow >= 3 && elevations.count >= elevationSmoothingWindow {
                let window = elevationSmoothingWindow % 2 == 1 ? elevationSmoothingWindow : elevationSmoothingWindow + 1
                processedElevations = smoothElevations(elevations, window: window)
            }
            
            // Calculate distance and elevation gain
            for i in 1..<seg.count {
                let prev = seg[i - 1]
                let curr = seg[i]
                let p1 = CLLocation(latitude: prev[1], longitude: prev[0])
                let p2 = CLLocation(latitude: curr[1], longitude: curr[0])
                totalMeters += p1.distance(from: p2)
                
                // Calculate elevation gain based on smoothing setting
                if elevationSmoothingEnabled {
                    // When ON: Use smoothed elevations with threshold
                    let deltaElev = processedElevations[i] - processedElevations[i - 1]
                    if deltaElev > elevationGainThresholdMeters {
                        totalAscentMeters += deltaElev
                    }
                } else {
                    // When OFF: Use raw elevations, count all positive changes
                    let deltaElev = elevations[i] - elevations[i - 1]
                    if deltaElev > 0 {
                        totalAscentMeters += deltaElev
                    }
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
    
    private func updatePOI(_ poi: PointOfInterest, newName: String, newColorName: String, newCategory: String) {
        let normalizedColorName = newColorName.lowercased()
        let updatedPOI = PointOfInterest(id: poi.id, name: newName, description: poi.description, coordinate: poi.coordinate, timestamp: poi.timestamp, category: newCategory, colorName: normalizedColorName)
        dataManager.updatePOI(updatedPOI)
    }
}

struct POIEditModal: View {
    let poi: PointOfInterest
    @Binding var name: String
    @Binding var colorName: String
    @Binding var category: String
    let dataManager: DataManager
    let onSave: (String, String, String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    private var allCategories: [String] {
        dataManager.customCategories.sorted()
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("POI Name") {
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
                
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(allCategories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    .pickerStyle(.wheel)
                }
            }
            .navigationTitle("Edit POI")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmedName, colorName, category)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || category.isEmpty)
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

