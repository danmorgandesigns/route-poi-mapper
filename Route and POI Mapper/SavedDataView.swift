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
    @State private var showingShareSheet = false
    @State private var shareContent = ""
    @State private var shareURL: URL? = nil
    
    @State private var routeToShare: TrailRoute? = nil
    @State private var selectedRouteForDetails: TrailRoute? = nil
    
    var body: some View {
        NavigationView {
            VStack {
                Picker("Data Type", selection: $selectedTab) {
                    Text("Routes").tag(0)
                    Text("POIs").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                if selectedTab == 0 {
                    RoutesListView(
                        dataManager: dataManager,
                        onExportFile: { route in
                            routeToShare = route
                        },
                        onShowDetails: { route in
                            selectedRouteForDetails = route
                        }
                    )
                } else {
                    POIsListView(dataManager: dataManager, onExport: { exportPOIs() })
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
            .sheet(isPresented: $showingShareSheet) {
                sheetContentView()
            }
            .sheet(item: $routeToShare) { route in
                RouteExportShareView(route: route)
            }
            .sheet(item: $selectedRouteForDetails) { route in
                RouteDetailsModal(route: route)
            }
        }
    }
    
    @ViewBuilder
    private func sheetContentView() -> some View {
        if let url = shareURL, let data = try? Data(contentsOf: url) {
            ShareSheetItems(items: [JSONItemProviderShareItem(data: data, filename: url.lastPathComponent)])
        } else {
            ShareSheet(content: shareContent)
        }
    }
    
    private func exportPOIs() {
        print("[POI Export] Button tapped")
        let start = Date()
        shareURL = dataManager.exportPOIsAsCustomJSONFile()
        let elapsed = Date().timeIntervalSince(start)
        if let url = shareURL {
            print("[POI Export] exportPOIsAsCustomJSONFile returned URL: \(url.absoluteString)")
            print("[POI Export] URL path exists? \(FileManager.default.fileExists(atPath: url.path))")
            do {
                let resourceValues = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .isRegularFileKey, .isDirectoryKey])
                print("[POI Export] isUbiquitousItem: \(String(describing: resourceValues.isUbiquitousItem))")
                print("[POI Export] isDirectory: \(String(describing: resourceValues.isDirectory))  isRegularFile: \(String(describing: resourceValues.isRegularFile))")
            } catch {
                print("[POI Export] Failed reading resource values for URL: \(error.localizedDescription)")
            }
        } else {
            print("[POI Export] exportPOIsAsCustomJSONFile returned nil URL")
        }
        print(String(format: "[POI Export] Elapsed: %.3fs", elapsed))
        shareContent = "" // not used when URL is present
        showingShareSheet = true
    }
}

struct RoutesListView: View {
    @ObservedObject var dataManager: DataManager
    let onExportFile: (TrailRoute) -> Void
    let onShowDetails: (TrailRoute) -> Void
    
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
                        onExportFile: { r in
                            onExportFile(r)
                        },
                        onShowDetails: { r in
                            onShowDetails(r)
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
    let onExportFile: (TrailRoute) -> Void
    let onShowDetails: (TrailRoute) -> Void
    
    private var formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(route.name)
                .font(.headline)
            
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
        .onTapGesture { onShowDetails(route) }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onExportFile(route)
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }.tint(.blue)
        }
    }
}

struct POIsListView: View {
    @ObservedObject var dataManager: DataManager
    let onExport: () -> Void
    
    @State private var showClearConfirm = false
    @State private var saveResultMessage: String? = nil
    @State private var showSaveResultAlert = false
    
    @State private var lastSavedPOIURL: URL? = nil
    @State private var showRevealSheet = false
    
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
                    if let url = dataManager.exportPOIsAsCustomJSONFile() {
                        lastSavedPOIURL = url
                        print("[Export] Generated file URL: \(url.absoluteString)")
                        showRevealSheet = true
                    } else {
                        print("[Export] Failed to generate file URL.")
                        saveResultMessage = "Failed to generate export file."
                        DispatchQueue.main.async { showSaveResultAlert = true }
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
        .sheet(isPresented: $showRevealSheet) {
            if let url = lastSavedPOIURL {
                ShareSheetItems(items: [JSONShareItem(fileURL: url)])
            } else {
                Text("No file to reveal.")
                    .padding()
            }
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
    
    // Helper function to get a system image for the category
    private func systemImageForCategory(_ category: String) -> String {
        switch category.lowercased() {
        case "animals": return "pawprint.fill"
        case "art installation": return "paintpalette.fill"
        case "building": return "building.2.fill"
        case "garden": return "leaf.fill"
        case "playground": return "figure.child"
        case "poi": return "mappin.circle.fill"
        case "restroom": return "toilet.fill"
        case "seat": return "chair.fill"
        case "shop": return "cart.fill"
        case "tree": return "tree.fill"
        default: return "mappin.circle.fill" // Default icon for unknown categories
        }
    }
    
    var body: some View {
        HStack {
            Image(systemName: systemImageForCategory(poi.category))
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

struct ShareSheet: UIViewControllerRepresentable {
    let content: String
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let items = [content]
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ShareSheetItems: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

final class JSONShareItem: NSObject, UIActivityItemSource {
    let fileURL: URL
    init(fileURL: URL) { self.fileURL = fileURL }
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return fileURL
    }
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return fileURL
    }
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        if #available(iOS 14.0, *) {
            return UTType.json.identifier
        } else {
            return "public.json"
        }
    }
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return fileURL.lastPathComponent
    }
}

final class JSONDataShareItem: NSObject, UIActivityItemSource {
    let data: Data
    let filename: String
    init(data: Data, filename: String) { self.data = data; self.filename = filename }
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return data
    }
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return data
    }
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        if #available(iOS 14.0, *) { return UTType.json.identifier } else { return "public.json" }
    }
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return filename
    }
    // Provide a suggested name for some activities
    func activityViewController(_ activityViewController: UIActivityViewController, thumbnailImageForActivityType activityType: UIActivity.ActivityType?, suggestedSize size: CGSize) -> UIImage? { nil }
}

final class JSONItemProviderShareItem: NSObject, UIActivityItemSource {
    let data: Data
    let filename: String
    init(data: Data, filename: String) { self.data = data; self.filename = filename }
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return NSItemProvider()
    }
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        if #available(iOS 14.0, *) {
            let provider = NSItemProvider(item: data as NSData, typeIdentifier: UTType.json.identifier)
            provider.suggestedName = filename
            return provider
        } else {
            let provider = NSItemProvider(item: data as NSData, typeIdentifier: "public.json")
            provider.suggestedName = filename
            return provider
        }
    }
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        if #available(iOS 14.0, *) { return UTType.json.identifier } else { return "public.json" }
    }
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return filename
    }
}

struct FolderPickerView: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

struct RouteDetailsModal: View {
    let route: TrailRoute
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(route.name)
                        .font(.title2).bold()
                    // Show the export JSON for clarity
                    let segments: [[[Double]]] = route.segments ?? [route.coordinates.map { [ $0.longitude, $0.latitude, $0.altitude ] }]
                    let (miles, feet) = {
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
                        return (totalMeters / 1609.344, totalAscentMeters * 3.28084)
                    }()
                    let infoString = String(format: "Length: %.2f miles. Elevation %.0f feet.", miles, feet)
                    let collection = route.exportGeoJSON(info: infoString)
                    if let data = try? JSONSerialization.data(withJSONObject: collection, options: .prettyPrinted),
                       let json = String(data: data, encoding: .utf8) {
                        Text(json)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text("Failed to render route JSON.")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Route Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}

struct RouteExportShareView: View {
    let route: TrailRoute

    @State private var exportURL: URL? = nil
    @State private var exportError: String? = nil
    
    var body: some View {
        Group {
            if let url = exportURL {
                ShareSheetItems(items: [ JSONShareItem(fileURL: url) ])
            } else if let error = exportError {
                Text(error)
            } else {
                // Minimal placeholder while preparing the export
                ProgressView("Preparing export…")
            }
        }
        .onAppear {
            prepareRouteExportFile()
        }
    }
    
    private func prepareRouteExportFile() {
        // Build segments and compute info string
        let segments: [[[Double]]] = route.segments ?? [route.coordinates.map { [ $0.longitude, $0.latitude, $0.altitude ] }]
        let (miles, feet) = computeDistanceMilesAndElevationFeet(from: segments)
        let infoString = String(format: "Length: %.2f miles. Elevation %.0f feet.", miles, feet)
        let collection = route.exportGeoJSON(info: infoString)

        // Serialize to JSON data
        guard let data = try? JSONSerialization.data(withJSONObject: collection, options: .prettyPrinted) else {
            exportError = "Failed to prepare export."
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

    // Keep existing distance computation helper
    private func computeDistanceMilesAndElevationFeet(from segments: [[[Double]]]) -> (Double, Double) {
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
        let miles = totalMeters / 1609.344
        let feet = totalAscentMeters * 3.28084
        return (miles, feet)
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

#Preview {
    SavedDataView(dataManager: DataManager())
}
