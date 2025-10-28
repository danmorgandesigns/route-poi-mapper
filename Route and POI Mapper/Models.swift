//
//  Models.swift
//  Route and POI Mapper
//
//  Created by Dan Morgan on 10/10/25.
//

import Foundation
import CoreLocation

// MARK: - Route Models

struct TrailRoute: Codable, Identifiable {
    let id: UUID
    let name: String
    let startTime: Date
    let endTime: Date?
    let coordinates: [TrailCoordinate]
    // Optional multi-segment storage: [[[lon, lat, elev], ...], ...]
    let segments: [[[Double]]]? // backward-compatible; nil means single segment implied by coordinates
    
    var colorName: String? = nil

    init(id: UUID = UUID(), name: String, startTime: Date, endTime: Date?, coordinates: [TrailCoordinate], segments: [[[Double]]]? = nil, colorName: String? = nil) {
        self.id = id
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.coordinates = coordinates
        self.segments = segments
        self.colorName = colorName
    }

    enum CodingKeys: String, CodingKey {
        case id, name, startTime, endTime, coordinates, segments, colorName
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try c.decode(String.self, forKey: .name)
        self.startTime = try c.decode(Date.self, forKey: .startTime)
        self.endTime = try c.decodeIfPresent(Date.self, forKey: .endTime)
        self.coordinates = try c.decode([TrailCoordinate].self, forKey: .coordinates)
        self.segments = try c.decodeIfPresent([[[Double]]].self, forKey: .segments)
        self.colorName = try c.decodeIfPresent(String.self, forKey: .colorName)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(startTime, forKey: .startTime)
        try c.encodeIfPresent(endTime, forKey: .endTime)
        try c.encode(coordinates, forKey: .coordinates)
        try c.encodeIfPresent(segments, forKey: .segments)
        try c.encodeIfPresent(colorName, forKey: .colorName)
    }

    // Legacy representation (kept for backward compatibility in UI code that still reads it)
    var geoJSON: [String: Any] {
        let coordinateArray = coordinates.map { [$0.longitude, $0.latitude] }
        return [
            "type": "Feature",
            "geometry": [
                "type": "LineString",
                "coordinates": coordinateArray
            ],
            "properties": [
                "name": name,
                "startTime": ISO8601DateFormatter().string(from: startTime),
                "endTime": endTime.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()
            ]
        ]
    }
    
    // Preferred export shape for files consumed by other apps
    func exportGeoJSON(info: String = "") -> [String: Any] {
        // Use stored segments if available; otherwise fall back to a single segment from coordinates with altitude
        let segs: [[[Double]]] = segments ?? [coordinates.map { [$0.longitude, $0.latitude, $0.altitude] }]
        let feature: [String: Any] = [
            "type": "Feature",
            "geometry": [
                "type": "MultiLineString",
                "coordinates": segs
            ],
            "properties": [
                "name": name,
                "description": "",
                "color": colorName ?? "",
                "info": info,
                "imageURL": ""
            ]
        ]
        return [
            "type": "FeatureCollection",
            "features": [feature]
        ]
    }
}

struct TrailCoordinate: Codable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let timestamp: Date
    let accuracy: Double
    
    init(from location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude
        self.timestamp = location.timestamp
        self.accuracy = location.horizontalAccuracy
    }
}

// MARK: - POI Models

struct PointOfInterest: Codable, Identifiable {
    let id: UUID
    let name: String
    let description: String
    let coordinate: POICoordinate
    let timestamp: Date
    let category: String // Changed from POICategory to String for custom categories
    var colorName: String? = nil
    
    init(id: UUID = UUID(), name: String, description: String, coordinate: POICoordinate, timestamp: Date, category: String, colorName: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.category = category
        self.colorName = colorName
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, description, coordinate, timestamp, category, colorName
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try c.decode(String.self, forKey: .name)
        self.description = try c.decode(String.self, forKey: .description)
        self.coordinate = try c.decode(POICoordinate.self, forKey: .coordinate)
        self.timestamp = try c.decode(Date.self, forKey: .timestamp)
        self.category = try c.decode(String.self, forKey: .category)
        self.colorName = try c.decodeIfPresent(String.self, forKey: .colorName)
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description)
        try c.encode(coordinate, forKey: .coordinate)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(category, forKey: .category)
        try c.encodeIfPresent(colorName, forKey: .colorName)
    }
}

struct POICoordinate: Codable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    
    init(from location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude
    }
    
    var clLocationCoordinate2D: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum POICategory: String, CaseIterable, Codable {
    case scenic = "Scenic View"
    case landmark = "Landmark"
    case hazard = "Hazard"
    case campsite = "Campsite"
    case water = "Water Source"
    case wildlife = "Wildlife"
    case other = "Other"
    
    var systemImage: String {
        switch self {
        case .scenic: return "camera.fill"
        case .landmark: return "flag.fill"
        case .hazard: return "exclamationmark.triangle.fill"
        case .campsite: return "tent.fill"
        case .water: return "drop.fill"
        case .wildlife: return "pawprint.fill"
        case .other: return "mappin.circle.fill"
        }
    }
}
