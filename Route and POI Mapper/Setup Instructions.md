//
//  Setup Instructions.md
//  Route and POI Mapper
//
//  Created by Dan Morgan on 10/10/25.
//

# Route and POI Mapper Setup Instructions

## Required Info.plist Permissions

Add the following keys to your app's Info.plist file to request location permissions:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app needs location access to track your hiking routes and record points of interest.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>This app needs location access to track your hiking routes and record points of interest.</string>
```

## Features Overview

### 1. **Route Tracking**
- Start/stop route tracking with GPS coordinates
- Real-time location monitoring with accuracy filtering
- Automatic coordinate collection every 5 meters
- Duration and point count tracking
- Save routes with custom names

### 2. **Points of Interest (POI)**
- Add POIs at current location while tracking
- Multiple categories: Scenic View, Landmark, Hazard, Campsite, Water Source, Wildlife, Other
- Include name, description, GPS coordinates, altitude, and timestamp
- Visual markers on map with category icons

### 3. **Data Management**
- Separate JSON file storage for routes and POIs
- Export individual routes or all routes as GeoJSON
- Export POIs as GeoJSON with feature collection format
- Delete individual routes and POIs
- Persistent local storage

### 4. **Map Integration**
- Real-time location display with user location tracking
- POI annotations with category-specific icons
- Route visualization (basic implementation)
- Interactive map with zoom and pan

## GeoJSON Export Formats

### Routes
```json
{
  "type": "Feature",
  "geometry": {
    "type": "LineString",
    "coordinates": [[longitude, latitude], ...]
  },
  "properties": {
    "name": "Trail Name",
    "startTime": "2025-10-10T10:00:00Z",
    "endTime": "2025-10-10T12:00:00Z"
  }
}
```

### POIs
```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": {
        "type": "Point",
        "coordinates": [longitude, latitude]
      },
      "properties": {
        "name": "POI Name",
        "description": "Description",
        "category": "Scenic View",
        "timestamp": "2025-10-10T11:00:00Z",
        "altitude": 1234.5
      }
    }
  ]
}
```

## File Structure

- **Models.swift**: Data models for routes, POIs, and coordinates
- **LocationManager.swift**: Core location tracking and permissions
- **DataManager.swift**: File I/O and GeoJSON export functionality
- **MapView.swift**: Map display with annotations
- **RouteTrackingView.swift**: Route tracking controls and status
- **AddPOIView.swift**: POI creation interface
- **SavedDataView.swift**: Saved data management and export
- **ContentView.swift**: Main app interface with tab navigation

## Usage Instructions

1. **Grant Location Permission**: App will request location access on first launch
2. **Start Tracking**: Go to "Tracking" tab and tap "Start Tracking"
3. **Add POIs**: While on the map, tap the blue pin button to add a POI at your current location
4. **Save Route**: After tracking, go to "Tracking" tab and tap "Save Route"
5. **Export Data**: Use "Saved Data" tab to export routes and POIs as GeoJSON files
6. **Share Files**: Use the iOS share sheet to save to Files app or share via email/messages

## Technical Notes

- Location accuracy is filtered to < 20 meters for better route quality
- Distance filter of 5 meters prevents excessive data collection
- Background location updates are disabled to avoid workout interference
- All data is stored locally in the app's Documents directory
- GeoJSON follows the RFC 7946 specification