//
//  POIExportManager.swift
//  Route and POI Mapper
//
//  Created by Assistant on 10/24/25.
//

import Foundation

// MARK: - Export Format Protocol

protocol POIExportFormat {
    var name: String { get }
    var fileExtension: String { get }
    var mimeType: String { get }
    
    func export(pois: [PointOfInterest]) throws -> Data
}

// MARK: - Export Error Types

enum POIExportError: LocalizedError {
    case noPOIsToExport
    case encodingFailed(String)
    case fileWriteFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noPOIsToExport:
            return "No POIs available to export"
        case .encodingFailed(let reason):
            return "Failed to encode POI data: \(reason)"
        case .fileWriteFailed(let reason):
            return "Failed to write export file: \(reason)"
        }
    }
}

// MARK: - JSON Export Format

struct JSONPOIExportFormat: POIExportFormat {
    let name = "JSON"
    let fileExtension = "json"
    let mimeType = "application/json"
    
    // Helper struct for stable JSON key ordering
    private struct ExportPOI: Encodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let category: String
        let description: String
        let imageURL: String
        
        // CodingKeys order defines the serialized key order
        enum CodingKeys: String, CodingKey {
            case name, latitude, longitude, category, description, imageURL
        }
    }
    
    func export(pois: [PointOfInterest]) throws -> Data {
        let exportItems: [ExportPOI] = pois.map { poi in
            ExportPOI(
                name: poi.name,
                latitude: poi.coordinate.latitude,
                longitude: poi.coordinate.longitude,
                category: poi.category,
                description: poi.description,
                imageURL: ""
            )
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        
        do {
            return try encoder.encode(exportItems)
        } catch {
            throw POIExportError.encodingFailed(error.localizedDescription)
        }
    }
}

// MARK: - CSV Export Format

struct CSVPOIExportFormat: POIExportFormat {
    let name = "CSV"
    let fileExtension = "csv"
    let mimeType = "text/csv"
    
    func export(pois: [PointOfInterest]) throws -> Data {
        var csvContent = "Name,Latitude,Longitude,Altitude,Category,Description,Timestamp\n"
        
        let dateFormatter = ISO8601DateFormatter()
        
        for poi in pois {
            // Escape CSV fields that might contain commas or quotes
            let name = escapeCSVField(poi.name)
            let category = escapeCSVField(poi.category)
            let description = escapeCSVField(poi.description)
            let timestamp = dateFormatter.string(from: poi.timestamp)
            
            let line = "\(name),\(poi.coordinate.latitude),\(poi.coordinate.longitude),\(poi.coordinate.altitude),\(category),\(description),\(timestamp)\n"
            csvContent += line
        }
        
        guard let data = csvContent.data(using: .utf8) else {
            throw POIExportError.encodingFailed("Failed to encode CSV as UTF-8")
        }
        
        return data
    }
    
    private func escapeCSVField(_ field: String) -> String {
        // If field contains comma, newline, or quote, wrap in quotes and escape internal quotes
        if field.contains(",") || field.contains("\n") || field.contains("\"") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }
}

// MARK: - GeoJSON Export Format

struct GeoJSONPOIExportFormat: POIExportFormat {
    let name = "geoJSON"
    let fileExtension = "geojson"
    let mimeType = "application/geo+json"
    
    func export(pois: [PointOfInterest]) throws -> Data {
        let features = pois.map { poi in
            [
                "type": "Feature",
                "geometry": [
                    "type": "Point",
                    "coordinates": [poi.coordinate.longitude, poi.coordinate.latitude, poi.coordinate.altitude]
                ],
                "properties": [
                    "name": poi.name,
                    "description": poi.description,
                    "category": poi.category,
                    "timestamp": ISO8601DateFormatter().string(from: poi.timestamp)
                ]
            ]
        }
        
        let featureCollection: [String: Any] = [
            "type": "FeatureCollection",
            "features": features
        ]
        
        do {
            return try JSONSerialization.data(withJSONObject: featureCollection, options: .prettyPrinted)
        } catch {
            throw POIExportError.encodingFailed(error.localizedDescription)
        }
    }
}

// MARK: - KML Export Format

struct KMLPOIExportFormat: POIExportFormat {
    let name = "KML"
    let fileExtension = "kml"
    let mimeType = "application/vnd.google-earth.kml+xml"
    
    func export(pois: [PointOfInterest]) throws -> Data {
        var kmlContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
          <Document>
            <name>POI Export</name>
            <description>Points of Interest exported by Gretel for iOS, developed by Dan Morgan Designs</description>
        
        """
        
        for poi in pois {
            let escapedName = xmlEscape(poi.name)
            let escapedDescription = xmlEscape(poi.description)
            let escapedCategory = xmlEscape(poi.category)
            
            kmlContent += """
            <Placemark>
              <name>\(escapedName)</name>
              <description><![CDATA[
                Category: \(escapedCategory)<br/>
                Description: \(escapedDescription)<br/>
                Timestamp: \(ISO8601DateFormatter().string(from: poi.timestamp))
              ]]></description>
              <Point>
                <coordinates>\(poi.coordinate.longitude),\(poi.coordinate.latitude),\(poi.coordinate.altitude)</coordinates>
              </Point>
            </Placemark>
            
            """
        }
        
        kmlContent += """
          </Document>
        </kml>
        """
        
        guard let data = kmlContent.data(using: .utf8) else {
            throw POIExportError.encodingFailed("Failed to encode KML as UTF-8")
        }
        
        return data
    }
    
    private func xmlEscape(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}


// MARK: - POI Export Manager

@MainActor
class POIExportManager {
    
    // Available export formats
    static let availableFormats: [POIExportFormat] = [
        JSONPOIExportFormat(),
        CSVPOIExportFormat(),
        GeoJSONPOIExportFormat(),
        KMLPOIExportFormat()
    ]
    
    // Get format by name
    static func format(named: String) -> POIExportFormat? {
        return availableFormats.first { $0.name.lowercased() == named.lowercased() }
    }
    
    // Export POIs to temporary file
    func exportPOIs(_ pois: [PointOfInterest], format: POIExportFormat) throws -> URL {
        guard !pois.isEmpty else {
            throw POIExportError.noPOIsToExport
        }
        
        let data = try format.export(pois: pois)
        
        // Generate filename with timestamp
        let timestamp = DateFormatter.exportTimestamp.string(from: Date())
        let filename = "POI-Export-\(timestamp).\(format.fileExtension)"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        do {
            // Remove existing file if it exists
            try? FileManager.default.removeItem(at: tempURL)
            
            // Write the file
            try data.write(to: tempURL, options: .atomic)
            
            return tempURL
        } catch {
            throw POIExportError.fileWriteFailed(error.localizedDescription)
        }
    }
}

// MARK: - Helper Extensions

fileprivate extension DateFormatter {
    static let exportTimestamp: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()
}