import Foundation

/// A utility for encoding segmented routes into GeoJSON FeatureCollection data.
/// 
/// Coordinates must be provided as arrays of [longitude, latitude, elevation].
/// The elevation value is included but not used for bounding box calculations.
/// 
/// Example usage:
/// ```swift
/// let segments: [[[Double]]] = [
///     [[-122.0, 37.0, 10.0], [-122.1, 37.1, 15.0]],
///     [[-122.2, 37.2, 5.0], [-122.3, 37.3, 0.0]]
/// ]
/// let data = try GeoJSONRouteEncoder.makeFeatureCollection(
///     name: "My Route",
///     segments: segments,
///     color: "#FF0000",
///     description: "Sample route",
///     info: "Additional info",
///     imageURL: nil
/// )
/// ```
public struct GeoJSONRouteEncoder {
    
    /// Creates a GeoJSON FeatureCollection Data representing the given segmented route.
    ///
    /// - Parameters:
    ///   - name: The name of the route.
    ///   - segments: An array of line segments where each segment is an array of coordinate triples [longitude, latitude, elevation].
    ///   - color: Optional color string for the route.
    ///   - description: Optional description of the route.
    ///   - info: Optional additional info.
    ///   - imageURL: Optional URL string for an image, serialized as null if nil.
    /// - Throws: An error if coordinate triples are invalid or JSON serialization fails.
    /// - Returns: GeoJSON FeatureCollection as pretty-printed JSON Data.
    public static func makeFeatureCollection(
        name: String,
        segments: [[[Double]]],
        color: String? = nil,
        description: String? = nil,
        info: String? = nil,
        imageURL: String? = nil
    ) throws -> Data {
        
        // Validate coordinate triples
        for segment in segments {
            for coordinate in segment {
                guard coordinate.count == 3 else {
                    throw GeoJSONRouteEncoderError.invalidCoordinateTriple(coordinate)
                }
            }
        }
        
        // Compute bounding box [minLon, minLat, maxLon, maxLat]
        var minLon: Double = Double.greatestFiniteMagnitude
        var minLat: Double = Double.greatestFiniteMagnitude
        var maxLon: Double = -Double.greatestFiniteMagnitude
        var maxLat: Double = -Double.greatestFiniteMagnitude
        
        var foundPoint = false
        for segment in segments {
            for coordinate in segment {
                let lon = coordinate[0]
                let lat = coordinate[1]
                if lon < minLon { minLon = lon }
                if lat < minLat { minLat = lat }
                if lon > maxLon { maxLon = lon }
                if lat > maxLat { maxLat = lat }
                foundPoint = true
            }
        }
        
        if !foundPoint {
            minLon = 0
            minLat = 0
            maxLon = 0
            maxLat = 0
        }
        
        // Prepare properties dictionary with required keys and default values
        let properties: [String: Any] = [
            "name": name,
            "description": description ?? "",
            "color": color ?? "",
            "info": info ?? "",
            "imageURL": imageURL as Any ?? NSNull()
        ]
        
        // Construct the GeoJSON dictionary
        let geojson: [String: Any] = [
            "type": "FeatureCollection",
            "bbox": [minLon, minLat, maxLon, maxLat],
            "features": [
                [
                    "type": "Feature",
                    "properties": properties,
                    "geometry": [
                        "type": "MultiLineString",
                        "coordinates": segments
                    ]
                ]
            ]
        ]
        
        // Serialize to JSON Data with pretty print
        let data = try JSONSerialization.data(withJSONObject: geojson, options: [.prettyPrinted])
        return data
    }
    
    /// Errors thrown by GeoJSONRouteEncoder
    public enum GeoJSONRouteEncoderError: Error, LocalizedError {
        case invalidCoordinateTriple([Double])
        
        public var errorDescription: String? {
            switch self {
            case .invalidCoordinateTriple(let triple):
                return "Invalid coordinate triple: \(triple). Each coordinate must have exactly 3 values [longitude, latitude, elevation]."
            }
        }
    }
}
