//
//  DataManager.swift
//  Route and POI Mapper
//
//  Created by Dan Morgan on 10/10/25.
//

import Foundation
import Combine

@MainActor
class DataManager: ObservableObject {
    @Published var savedRoutes: [TrailRoute] = []
    @Published var savedPOIs: [PointOfInterest] = []
    @Published var customCategories: [String] = []
    
    // MARK: - Export Helper (Stable Key Order)
    private struct ExportPOI: Encodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let category: String
        let description: String
        let imageURL: String
        
        // CodingKeys order defines the serialized key order
        enum CodingKeys: String, CodingKey {
            case name
            case latitude
            case longitude
            case category
            case description
            case imageURL
        }
    }
    
    private let routesFileName = "saved_routes.json"
    private let poisFileName = "saved_pois.json"
    private let categoriesFileName = "custom_categories.json"
    
    private let gretelBookmarkKey = "GretelFolderBookmark"
    
    private func ensureICloudGretelFolder() throws -> URL {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            throw NSError(domain: "DataManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "iCloud Drive not available or entitlement missing."])
        }
        let docsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        let gretelURL = docsURL.appendingPathComponent("Gretel", isDirectory: true)
        try FileManager.default.createDirectory(at: gretelURL, withIntermediateDirectories: true)
        return gretelURL
    }
    
    init() {
        loadRoutes()
        loadPOIs()
        loadCustomCategories()
    }
    
    // MARK: - Routes Management
    
    func saveRoute(_ route: TrailRoute) {
        savedRoutes.append(route)
        saveRoutesToFile()
    }
    
    func deleteRoute(_ route: TrailRoute) {
        savedRoutes.removeAll { $0.id == route.id }
        saveRoutesToFile()
    }
    
    func updateRoute(_ updated: TrailRoute) {
        if let index = savedRoutes.firstIndex(where: { $0.id == updated.id }) {
            savedRoutes[index] = updated
            saveRoutesToFile()
        }
    }
    
    func exportRouteAsGeoJSON(_ route: TrailRoute) -> String {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: route.geoJSON, options: .prettyPrinted)
            return String(data: jsonData, encoding: .utf8) ?? ""
        } catch {
            print("Error exporting GeoJSON: \(error)")
            return ""
        }
    }
    
    func exportAllRoutesAsGeoJSON() -> String {
        let featureCollection: [String: Any] = [
            "type": "FeatureCollection",
            "features": savedRoutes.map { $0.geoJSON }
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: featureCollection, options: .prettyPrinted)
            return String(data: jsonData, encoding: .utf8) ?? ""
        } catch {
            print("Error exporting GeoJSON collection: \(error)")
            return ""
        }
    }
    
    // MARK: - GeoJSON Route File Persistence
    func saveGeoJSONRouteFile(named name: String, data: Data) -> URL? {
        let safeName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let filename = safeName.isEmpty ? "Route.geojson" : safeName + ".geojson"
        let url = getDocumentsURL().appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            print("Error writing GeoJSON route file: \(error)")
            return nil
        }
    }
    
    private func saveRoutesToFile() {
        do {
            let data = try JSONEncoder().encode(savedRoutes)
            let url = getDocumentsURL().appendingPathComponent(routesFileName)
            try data.write(to: url)
        } catch {
            print("Error saving routes: \(error)")
        }
    }
    
    private func loadRoutes() {
        do {
            let url = getDocumentsURL().appendingPathComponent(routesFileName)
            let data = try Data(contentsOf: url)
            savedRoutes = try JSONDecoder().decode([TrailRoute].self, from: data)
        } catch {
            print("Error loading routes: \(error)")
            savedRoutes = []
        }
    }
    
    // MARK: - POIs Management
    
    func savePOI(_ poi: PointOfInterest) {
        savedPOIs.append(poi)
        savePOIsToFile()
    }
    
    func deletePOI(_ poi: PointOfInterest) {
        savedPOIs.removeAll { $0.id == poi.id }
        savePOIsToFile()
    }
    
    func clearAllPOIs() {
        // Clear in-memory array first so UI updates immediately
        savedPOIs.removeAll()
        
        // Clear persisted POIs file
        let url = getDocumentsURL().appendingPathComponent(poisFileName)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                // Overwrite with an empty array to keep file present but empty
                let emptyData = try JSONEncoder().encode([PointOfInterest]())
                try emptyData.write(to: url, options: .atomic)
            } else {
                // If file doesn't exist, nothing to do
            }
        } catch {
            print("Error clearing POIs: \(error)")
        }
    }
    
    func exportPOIsAsGeoJSON() -> String {
        let features = savedPOIs.map { poi in
            [
                "type": "Feature",
                "geometry": [
                    "type": "Point",
                    "coordinates": [poi.coordinate.longitude, poi.coordinate.latitude]
                ],
                "properties": [
                    "name": poi.name,
                    "description": poi.description,
                    "category": poi.category,
                    "timestamp": ISO8601DateFormatter().string(from: poi.timestamp),
                    "altitude": poi.coordinate.altitude
                ]
            ] as [String: Any]
        }
        
        let featureCollection: [String: Any] = [
            "type": "FeatureCollection",
            "features": features
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: featureCollection, options: .prettyPrinted)
            return String(data: jsonData, encoding: .utf8) ?? ""
        } catch {
            print("Error exporting POIs GeoJSON: \(error)")
            return ""
        }
    }
    
    func exportPOIsAsCustomJSONFile() -> URL? {
        // Build array of ExportPOI to guarantee key order
        let exportItems: [ExportPOI] = savedPOIs.map { poi in
            ExportPOI(
                name: poi.name,
                latitude: poi.coordinate.latitude,
                longitude: poi.coordinate.longitude,
                category: poi.category,
                description: "",
                imageURL: ""
            )
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            let data = try encoder.encode(exportItems)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let filename = formatter.string(from: Date()) + ".json"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: tempURL)
            try data.write(to: tempURL, options: .atomic)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: tempURL.path), let size = attrs[.size] as? NSNumber {
                print("[POI Export] Wrote temp file:", tempURL.lastPathComponent, "size:", size, "bytes")
            }
            return tempURL
        } catch {
            print("Error exporting custom POIs JSON: \(error)")
            return nil
        }
    }
    
    func exportPOIsAsCustomJSONData() -> (data: Data, filename: String)? {
        let exportItems: [ExportPOI] = savedPOIs.map { poi in
            ExportPOI(
                name: poi.name,
                latitude: poi.coordinate.latitude,
                longitude: poi.coordinate.longitude,
                category: poi.category,
                description: "",
                imageURL: ""
            )
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            let data = try encoder.encode(exportItems)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let filename = formatter.string(from: Date()) + ".json"
            return (data, filename)
        } catch {
            print("Error exporting custom POIs JSON (data): \(error)")
            return nil
        }
    }
    
    func savePOIsToICloudGretel() throws -> URL {
        print("[iCloud] Begin savePOIsToICloudGretel")
        // Build JSON data with stable key order
        let exportItems: [ExportPOI] = savedPOIs.map { poi in
            ExportPOI(
                name: poi.name,
                latitude: poi.coordinate.latitude,
                longitude: poi.coordinate.longitude,
                category: poi.category,
                description: "",
                imageURL: ""
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(exportItems)
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        let filename = formatter.string(from: Date()) + ".json"

        // Ensure Gretel folder exists in iCloud container
        let gretelURL = try ensureICloudGretelFolder()
        print("[iCloud] Gretel folder:", gretelURL.path)

        let fileURL = gretelURL.appendingPathComponent(filename)
        print("[iCloud] Target file:", fileURL.path)

        do {
            try data.write(to: fileURL, options: .atomic)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path), let size = attrs[.size] as? NSNumber {
                print("[iCloud] Wrote file (\(size) bytes)")
            } else {
                print("[iCloud] Wrote file (size unknown)")
            }
        } catch {
            print("[iCloud][Error] Writing file failed:", error.localizedDescription)
            throw error
        }

        print("[iCloud] Save complete")
        return fileURL
    }
    
    private func savePOIsToFile() {
        do {
            let data = try JSONEncoder().encode(savedPOIs)
            let url = getDocumentsURL().appendingPathComponent(poisFileName)
            try data.write(to: url)
        } catch {
            print("Error saving POIs: \(error)")
        }
    }
    
    private func loadPOIs() {
        do {
            let url = getDocumentsURL().appendingPathComponent(poisFileName)
            let data = try Data(contentsOf: url)
            savedPOIs = try JSONDecoder().decode([PointOfInterest].self, from: data)
        } catch {
            print("Error loading POIs: \(error)")
            savedPOIs = []
        }
    }
    
    // MARK: - Helper Methods
    
    // MARK: - Custom Categories Management
    
    func addCustomCategory(_ category: String) {
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCategory.isEmpty && !customCategories.contains(trimmedCategory) {
            customCategories.append(trimmedCategory)
            saveCustomCategories()
        }
    }
    
    func removeCustomCategory(_ category: String) {
        customCategories.removeAll { $0 == category }
        saveCustomCategories()
    }
    
    private func saveCustomCategories() {
        do {
            let data = try JSONEncoder().encode(customCategories)
            let url = getDocumentsURL().appendingPathComponent(categoriesFileName)
            try data.write(to: url)
        } catch {
            print("Error saving custom categories: \(error)")
        }
    }
    
    private func loadCustomCategories() {
        do {
            let url = getDocumentsURL().appendingPathComponent(categoriesFileName)
            let data = try Data(contentsOf: url)
            customCategories = try JSONDecoder().decode([String].self, from: data)
        } catch {
            // Initialize with default categories if no saved data exists
            customCategories = [
                "Animals",
                "Art Installation", 
                "Building",
                "Garden",
                "Playground",
                "POI",
                "Restroom",
                "Seat",
                "Shop",
                "Tree"
            ]
            saveCustomCategories()
        }
    }
    
    // MARK: - Helper Methods
    
    private func getDocumentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    func getDocumentsDirectory() -> String {
        getDocumentsURL().path
    }
    
    // MARK: - iCloud Drive (Security-Scoped Bookmark) Helpers
    func storeGretelFolderBookmark(from url: URL) {
        do {
            let dirURL = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
            let bookmark = try dirURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: gretelBookmarkKey)
            print("[iCloud] Stored Gretel folder bookmark:", dirURL.path)
        } catch {
            print("[iCloud][Error] Storing bookmark:", error.localizedDescription)
        }
    }
    
    func resolveGretelFolderBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: gretelBookmarkKey) else { return nil }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            if stale {
                print("[iCloud] Bookmark is stale; needs re-selection")
                return nil
            }
            return url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        } catch {
            print("[iCloud][Error] Resolving bookmark:", error.localizedDescription)
            return nil
        }
    }
    
    func savePOIsToBookmarkedGretelFolder() throws -> URL {
        // Build JSON data with stable key order
        let exportItems: [ExportPOI] = savedPOIs.map { poi in
            ExportPOI(
                name: poi.name,
                latitude: poi.coordinate.latitude,
                longitude: poi.coordinate.longitude,
                category: poi.category,
                description: "",
                imageURL: ""
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(exportItems)
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        let filename = formatter.string(from: Date()) + ".json"
        
        // Try bookmarked folder first; if not available, fall back to app's iCloud Gretel folder
        var didStartAccess = false
        let folderURL: URL
        if let bookmarked = resolveGretelFolderBookmark() {
            if bookmarked.startAccessingSecurityScopedResource() {
                didStartAccess = true
                folderURL = bookmarked
                print("[iCloud] Using bookmarked Gretel folder:", folderURL.path)
            } else {
                print("[iCloud][Warn] Unable to access bookmarked folder; falling back to iCloud Gretel")
                folderURL = try ensureICloudGretelFolder()
            }
        } else {
            print("[iCloud] No bookmark found; using iCloud Gretel folder")
            folderURL = try ensureICloudGretelFolder()
        }
        defer { if didStartAccess { folderURL.stopAccessingSecurityScopedResource() } }
        
        // Ensure folder exists (in case user moved/renamed, we still try to create)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let fileURL = folderURL.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)
        print("[iCloud] Wrote to bookmarked folder:", fileURL.path)
        return fileURL
    }
}

