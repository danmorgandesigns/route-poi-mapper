//
//  MapView.swift
//  Route and POI Mapper
//
//  Created by Dan Morgan on 10/10/25.
//

import SwiftUI
import MapKit
import Combine
import UIKit
import CoreLocation

final class ColoredPolyline: MKPolyline {
    var color: UIColor = .systemBlue
}

struct MapView: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var dataManager: DataManager
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // San Francisco default
        span: MKCoordinateSpan(latitudeDelta: 0.0015, longitudeDelta: 0.0015)
    )
    
    @State private var showingPOISheet = false
    @State private var selectedPOILocation: CLLocation?
    @State private var mapType: MKMapType = .satellite
    @State private var showingQuickPOIModal = false
    @State private var showingRouteModal = false
    @State private var showingFolderModal = false
    @State private var showingRouteNameModal = false
    @State private var didCenterInitially = false
    @State private var showingSettings = false
    @State private var showingInfo: Bool = false

    @State private var showingLocationDisabledModal = false
    @State private var pendingActionAfterLocationEnable: (() -> Void)? = nil
    
    @State private var suppressAutoCenter = false
    @State private var allowRegionSync = true
    
    @State private var isLocationEnabled = true
    
    private func uiColor(for name: String) -> UIColor {
        switch name.lowercased() {
        case "black": return .black
        case "blue": return .systemBlue
        case "brown": return .brown
        case "cyan": return .cyan
        case "gray", "grey": return .systemGray
        case "green": return .systemGreen
        case "indigo": return UIColor { trait in
            return UIColor.systemIndigo
        }
        case "mint": return UIColor { _ in
            return UIColor.systemMint
        }
        case "orange": return .systemOrange
        case "pink": return UIColor { _ in
            return UIColor.systemPink
        }
        case "purple": return .systemPurple
        case "teal": return UIColor { _ in
            return UIColor.systemTeal
        }
        case "white": return .white
        case "yellow": return .systemYellow
        default: return .systemBlue
        }
    }
    
    private var activeRoutePolylines: [MKPolyline] {
        var lines: [MKPolyline] = []
        // Finalized segments
        for segment in locationManager.currentSegments {
            let coords = segment.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
            if !coords.isEmpty {
                lines.append(MKPolyline(coordinates: coords, count: coords.count))
            }
        }
        // Active segment (if any) built from currentRoute tail since currentSegment isn't published
        // Fall back to building from the last N points in currentRoute to approximate the active segment
        // Note: For more precise rendering, consider publishing currentSegment in LocationManager
        if locationManager.isTracking && !locationManager.isPaused {
            // Try to infer the active segment by taking recent points since last pause
            // As a simple approach, draw the entire currentRoute as the active line if no segments exist yet
            let coords = locationManager.currentRoute.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            if coords.count > 1 {
                lines.append(MKPolyline(coordinates: coords, count: coords.count))
            }
        }
        return lines
    }
    
    private var savedPolylines: [MKPolyline] {
        var lines: [MKPolyline] = []
        for route in dataManager.savedRoutes {
            let segs: [[[Double]]] = route.segments ?? [route.coordinates.map { [ $0.longitude, $0.latitude, $0.altitude ] }]
            let colorName = route.colorName ?? "blue"
            let color = uiColor(for: colorName)
            for seg in segs {
                let coords = seg.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                guard coords.count > 1 else { continue }
                let poly = ColoredPolyline(coordinates: coords, count: coords.count)
                poly.color = color
                lines.append(poly)
            }
        }
        return lines
    }
    
    private var savedRouteMidpointAnnotations: [RouteMidpointAnnotation] {
        var annotations: [RouteMidpointAnnotation] = []
        for route in dataManager.savedRoutes {
            let segs: [[[Double]]] = route.segments ?? [route.coordinates.map { [ $0.longitude, $0.latitude, $0.altitude ] }]
            // Flatten all coords in order
            let coords = segs.flatMap { $0 }.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
            guard coords.count > 1 else { continue }
            
            // Compute total length
            var totalLength: CLLocationDistance = 0
            for i in 1..<coords.count {
                let p1 = CLLocation(latitude: coords[i-1].latitude, longitude: coords[i-1].longitude)
                let p2 = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
                totalLength += p1.distance(from: p2)
            }
            guard totalLength > 0 else { continue }
            
            let halfLength = totalLength / 2
            
            // Walk coords to find midpoint along the route
            var accLength: CLLocationDistance = 0
            var midpointCoordinate: CLLocationCoordinate2D? = nil
            for i in 1..<coords.count {
                let p1 = CLLocation(latitude: coords[i-1].latitude, longitude: coords[i-1].longitude)
                let p2 = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
                let segmentLength = p1.distance(from: p2)
                
                if accLength + segmentLength >= halfLength {
                    let needed = halfLength - accLength
                    let fraction = needed / segmentLength
                    let lat = coords[i-1].latitude + (coords[i].latitude - coords[i-1].latitude) * fraction
                    let lon = coords[i-1].longitude + (coords[i].longitude - coords[i-1].longitude) * fraction
                    midpointCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    break
                } else {
                    accLength += segmentLength
                }
            }
            if let midCoord = midpointCoordinate {
                let annotation = RouteMidpointAnnotation()
                annotation.coordinate = midCoord
                annotation.title = route.name
                annotation.routeName = route.name
                annotations.append(annotation)
            }
        }
        return annotations
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                let saved = savedPolylines
                UIKitMapView(
                    region: $region,
                    mapType: $mapType,
                    polylines: activeRoutePolylines + saved,
                    activeCount: activeRoutePolylines.count,
                    poiAnnotations: poiAnnotations,
                    routeMidpointAnnotations: savedRouteMidpointAnnotations,
                    allowRegionSync: allowRegionSync,
                    showsUserLocation: isLocationEnabled,
                    onUserInteraction: { suppressAutoCenter = true; allowRegionSync = false }
                )
                .ignoresSafeArea(.all)
                .onReceive(locationManager.$location) { location in
                    if isLocationEnabled {
                        if let location = location {
                            if !didCenterInitially {
                                didCenterInitially = true
                                withAnimation { region.center = location.coordinate }
                            }
                            if locationManager.isTracking && !suppressAutoCenter {
                                withAnimation { region.center = location.coordinate }
                            }
                        }
                    }
                }
                .onReceive(dataManager.$savedPOIs) { poIs in
                    // Only recenter if tracking (as previously)
                    if locationManager.isTracking {
                        guard let latest = poIs.last else { return }
                        region.center = latest.coordinate.clLocationCoordinate2D
                    }
                }
                
                // Route info overlay with subtle material effect
                VStack {
                    Spacer()
                    
                    if locationManager.isTracking {
                        RouteInfoOverlay(locationManager: locationManager)
                            .padding(.horizontal, 20)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .bottomBar)
            .toolbarColorScheme(.dark, for: .bottomBar) // Force transparent bottom toolbar
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 16) {
                        Button(action: {
                            mapType = mapType == .satellite ? .standard : .satellite
                        }) {
                            Image(systemName: mapType == .satellite ? "globe" : "map")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                                .padding(.leading, 6)
                        }
                        
                        Button(action: {
                            isLocationEnabled.toggle()
                            if isLocationEnabled {
                                suppressAutoCenter = false
                                allowRegionSync = true
                                if let location = locationManager.location {
                                    withAnimation {
                                        region.center = location.coordinate
                                    }
                                }
                            } else {
                                suppressAutoCenter = true
                                allowRegionSync = false
                            }
                        }) {
                            Image(systemName: isLocationEnabled ? "location" : "location.slash")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                                .padding(.trailing, 6)
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                                .padding(.leading, 6)
                        }
                        Button(action: {
                            showingInfo = true
                        }) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                                .padding(.trailing, 6)
                        }
                    }
                }

                
                // Bottom toolbar items 
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button(action: {
                            if !isLocationEnabled {
                                // Defer the intended action until user enables location
                                pendingActionAfterLocationEnable = { showingRouteModal = true }
                                showingLocationDisabledModal = true
                            } else {
                                showingRouteModal = true
                            }
                        }) {
                            Image(systemName: "figure.hiking")
                        }
                        .padding(.leading, 20)  // Push hiking button right
                        
                        Spacer()
                        
                        Button(action: {
                            if !isLocationEnabled {
                                pendingActionAfterLocationEnable = {
                                    if let currentLocation = locationManager.location {
                                        selectedPOILocation = currentLocation
                                        DispatchQueue.main.async { showingQuickPOIModal = true }
                                    } else {
                                        let dummyLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
                                        selectedPOILocation = dummyLocation
                                        DispatchQueue.main.async { showingQuickPOIModal = true }
                                    }
                                }
                                showingLocationDisabledModal = true
                            } else {
                                if let currentLocation = locationManager.location {
                                    selectedPOILocation = currentLocation
                                    DispatchQueue.main.async { showingQuickPOIModal = true }
                                } else {
                                    let dummyLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
                                    selectedPOILocation = dummyLocation
                                    DispatchQueue.main.async { showingQuickPOIModal = true }
                                }
                            }
                        }) {
                            Image(systemName: "mappin.and.ellipse")
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            showingFolderModal = true
                        }) {
                            Image(systemName: "folder")
                        }
                        .padding(.trailing, 20)  // Push folder button left
                    }
                }
            }
        }
        .sheet(isPresented: $showingPOISheet) {
            if let location = selectedPOILocation {
                AddPOIView(location: location, dataManager: dataManager)
            }
        }
        .sheet(isPresented: $showingQuickPOIModal) {
            QuickPOIModal(
                location: selectedPOILocation,
                locationManager: locationManager,
                dataManager: dataManager
            )
        }
        .sheet(isPresented: $showingRouteModal) {
            RouteConfirmationModal(locationManager: locationManager, isRouteNameSheetPresented: $showingRouteNameModal)
        }
        .sheet(isPresented: $showingRouteNameModal) {
            RouteNamingModal { name in
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallbackName: String = {
                    let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                    return "Route-\(df.string(from: Date()))"
                }()
                let finalName = trimmedName.isEmpty ? fallbackName : trimmedName

                // Build and persist the route model first (now includes segments)
                if let route = locationManager.createTrailRoute(name: finalName) {
                    dataManager.saveRoute(route)

                    // Build segments array for metrics
                    let segments: [[[Double]]]
                    if let segs = route.segments { segments = segs } else {
                        let single = route.coordinates.map { [ $0.longitude, $0.latitude, $0.altitude ] }
                        segments = single.isEmpty ? [] : [single]
                    }

                    // Compute distance (miles) and elevation gain (feet)
                    func computeDistanceMilesAndElevationFeet(from segments: [[[Double]]]) -> (Double, Double) {
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

                    let (miles, feet) = computeDistanceMilesAndElevationFeet(from: segments)
                    let infoString = String(format: "Length: %.2f miles. Elevation %.0f feet.", miles, feet)

                    // Use the centralized export shape from the model
                    let collection = route.exportGeoJSON(info: infoString)
                    do {
                        let data = try JSONSerialization.data(withJSONObject: collection, options: .prettyPrinted)
                        if data.isEmpty {
                            print("[Route Export] exportGeoJSON produced empty data for route: \(finalName)")
                        } else {
                            if let url = dataManager.saveGeoJSONRouteFile(named: finalName, data: data) {
                                print("[Route Export] Wrote .geojson file: \(url.lastPathComponent)")
                            } else {
                                print("[Route Export] Failed to write .geojson file for route: \(finalName)")
                            }
                        }
                    } catch {
                        print("[Route Export] Failed to serialize exportGeoJSON: \(error)")
                    }
                } else {
                    print("[Route Export] Failed to create TrailRoute for name: \(finalName)")
                }
            }
        }
        .sheet(isPresented: $showingFolderModal) {
            SavedDataView(dataManager: dataManager)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingInfo) {
            InfoView()
        }
        .confirmationDialog(
            "Location is turned off",
            isPresented: $showingLocationDisabledModal,
            titleVisibility: .visible
        ) {
            Button("Turn On Location") {
                isLocationEnabled = true
                suppressAutoCenter = false
                allowRegionSync = true
                if let location = locationManager.location {
                    withAnimation { region.center = location.coordinate }
                }
                // Perform the deferred action if any
                pendingActionAfterLocationEnable?()
                pendingActionAfterLocationEnable = nil
            }
            Button("Cancel", role: .cancel) {
                pendingActionAfterLocationEnable = nil
            }
        } message: {
            Text("Location services for the map are currently disabled. Turn it on to proceed.")
        }
    }
    
    private var poiAnnotations: [PointOfInterest] {
        dataManager.savedPOIs
    }
}

struct CapsuleLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.regularMaterial, in: Capsule())
    }
}

final class RouteMidpointAnnotation: MKPointAnnotation {
    var routeName: String = ""
}

// New POIAnnotation class with poiName property
final class POIAnnotation: MKPointAnnotation {
    var poiName: String = ""
}

struct UIKitMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @Binding var mapType: MKMapType
    var polylines: [MKPolyline]
    var activeCount: Int
    var poiAnnotations: [PointOfInterest]
    var routeMidpointAnnotations: [RouteMidpointAnnotation] = []
    
    var allowRegionSync: Bool = true
    var showsUserLocation: Bool = true
    
    var onUserInteraction: (() -> Void)? = nil
    
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsUserLocation = showsUserLocation
        map.mapType = mapType
        map.region = region
        return map
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        if allowRegionSync {
            if uiView.region.center.latitude != region.center.latitude ||
                uiView.region.center.longitude != region.center.longitude ||
                uiView.region.span.latitudeDelta != region.span.latitudeDelta ||
                uiView.region.span.longitudeDelta != region.span.longitudeDelta {
                uiView.setRegion(region, animated: false)
            }
        }
        if uiView.mapType != mapType { uiView.mapType = mapType }
        if uiView.showsUserLocation != showsUserLocation { uiView.showsUserLocation = showsUserLocation }
        // Update overlays
        uiView.removeOverlays(uiView.overlays)
        uiView.addOverlays(polylines)
        // Update POI annotations
        uiView.removeAnnotations(uiView.annotations.filter { !($0 is MKUserLocation) })
        
        // Use POIAnnotation instead of MKPointAnnotation for POIs
        let annotations = poiAnnotations.map { poi -> POIAnnotation in
            let ann = POIAnnotation()
            ann.poiName = poi.name
            ann.title = poi.name
            ann.coordinate = poi.coordinate.clLocationCoordinate2D
            return ann
        }
        uiView.addAnnotations(annotations)
        
        // Add route midpoint annotations
        uiView.addAnnotations(routeMidpointAnnotations)
    }
    
    // PaddingLabel helper to provide intrinsic content padding around text
    final class PaddingLabel: UILabel {
        var insets = UIEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)
        override func drawText(in rect: CGRect) {
            super.drawText(in: rect.inset(by: insets))
        }
        override var intrinsicContentSize: CGSize {
            let size = super.intrinsicContentSize
            return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
        }
    }
    
    // Shared helper to build a capsule label matching trail route style
    func makeCapsuleLabel(text: String) -> (view: PaddingLabel, size: CGSize, font: UIFont) {
        let font = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize, weight: .semibold)
        let maxLabelWidth: CGFloat = 280
        let textSize = (text as NSString).boundingRect(
            with: CGSize(width: maxLabelWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).size
        let labelPaddingH: CGFloat = 4
        let labelPaddingV: CGFloat = 2
        let labelWidth = min(maxLabelWidth, ceil(textSize.width) + labelPaddingH * 2)
        let labelHeight = ceil(font.lineHeight) + labelPaddingV * 2
        let label = PaddingLabel()
        label.text = text
        label.font = font
        label.textAlignment = .center
        label.textColor = UIColor.label
        label.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.7)
        label.layer.cornerRadius = labelHeight / 2
        label.clipsToBounds = true
        return (label, CGSize(width: labelWidth, height: labelHeight), font)
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    final class Coordinator: NSObject, MKMapViewDelegate {
        let parent: UIKitMapView
        init(_ parent: UIKitMapView) { self.parent = parent }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                let idx = parent.polylines.firstIndex(of: polyline) ?? 0
                let isActive = idx < parent.activeCount
                if isActive {
                    renderer.strokeColor = UIColor.systemRed
                } else if let colored = polyline as? ColoredPolyline {
                    renderer.strokeColor = colored.color
                } else {
                    renderer.strokeColor = UIColor.systemBlue
                }
                renderer.lineWidth = 4
                renderer.lineJoin = .round
                renderer.lineCap = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            if let routeMidpoint = annotation as? RouteMidpointAnnotation {
                let id = "RouteMidpointAnnotation"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                if annotationView == nil {
                    annotationView = MKAnnotationView(annotation: routeMidpoint, reuseIdentifier: id)
                    annotationView?.canShowCallout = false
                    
                    // Container sized to fit icon + label
                    let iconDiameter: CGFloat = 24
                    let spacing: CGFloat = 2
                    
                    // Measure label width somewhat generously; we'll cap later
                    let nameText = routeMidpoint.routeName
                    let (label, labelSize, _) = parent.makeCapsuleLabel(text: nameText)
                    
                    let container = UIView(frame: CGRect(x: 0, y: 0, width: max(iconDiameter, labelSize.width), height: iconDiameter + spacing + labelSize.height))
                    container.backgroundColor = .clear
                    
                    // Brown circular icon
                    let circleView = UIView(frame: CGRect(x: (container.bounds.width - iconDiameter)/2, y: 0, width: iconDiameter, height: iconDiameter))
                    circleView.backgroundColor = UIColor.brown
                    circleView.layer.cornerRadius = iconDiameter / 2
                    circleView.clipsToBounds = true
                    
                    let imageView = UIImageView(frame: circleView.bounds)
                    imageView.contentMode = .center
                    let config = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
                    imageView.image = UIImage(systemName: "figure.hiking", withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal)
                    
                    circleView.addSubview(imageView)
                    container.addSubview(circleView)
                    
                    label.frame = CGRect(x: (container.bounds.width - labelSize.width)/2, y: iconDiameter + spacing, width: labelSize.width, height: labelSize.height)
                    container.addSubview(label)
                    
                    annotationView?.subviews.forEach { $0.removeFromSuperview() }
                    annotationView?.addSubview(container)
                    annotationView?.frame = container.frame
                    annotationView?.centerOffset = CGPoint(x: 0, y: -(container.frame.height / 2))
                } else {
                    annotationView?.annotation = routeMidpoint
                    // Update label text
                    if let container = annotationView?.subviews.first {
                        for subview in container.subviews {
                            if let label = subview as? UILabel {
                                let nameText = routeMidpoint.routeName
                                label.text = nameText
                                
                                let iconDiameter: CGFloat = 24
                                let spacing: CGFloat = 2
                                
                                let (_, labelSize, _) = parent.makeCapsuleLabel(text: nameText)
                                
                                label.frame = CGRect(x: (container.bounds.width - labelSize.width)/2, y: iconDiameter + spacing, width: labelSize.width, height: labelSize.height)
                                
                                // Also update container and annotationView frame
                                let containerWidth = max(iconDiameter, labelSize.width)
                                let containerHeight = iconDiameter + spacing + labelSize.height
                                
                                container.frame = CGRect(x: 0, y: 0, width: containerWidth, height: containerHeight)
                                annotationView?.frame = container.frame
                                annotationView?.centerOffset = CGPoint(x: 0, y: -(container.frame.height / 2))
                            }
                        }
                    }
                }
                return annotationView
            }
            
            if let poiAnnotation = annotation as? POIAnnotation {
                let id = "POIAnnotationView"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                let iconDiameter: CGFloat = 24
                let spacing: CGFloat = 2
                let nameText = poiAnnotation.poiName
                
                if annotationView == nil {
                    annotationView = MKAnnotationView(annotation: poiAnnotation, reuseIdentifier: id)
                    annotationView?.canShowCallout = false
                    
                    // Remove existing subviews if any (defensive)
                    annotationView?.subviews.forEach { $0.removeFromSuperview() }
                    
                    let container = UIView(frame: CGRect(x: 0, y: 0, width: iconDiameter, height: iconDiameter))
                    container.backgroundColor = .clear
                    
                    let circleView = UIView(frame: CGRect(x: (container.bounds.width - iconDiameter)/2, y: 0, width: iconDiameter, height: iconDiameter))
                    circleView.backgroundColor = UIColor.systemRed
                    circleView.layer.cornerRadius = iconDiameter / 2
                    circleView.clipsToBounds = true
                    circleView.tag = 1001
                    
                    let imageView = UIImageView(frame: circleView.bounds)
                    imageView.contentMode = .center
                    let config = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
                    imageView.image = UIImage(systemName: "mappin.and.ellipse", withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal)
                    
                    circleView.addSubview(imageView)
                    container.addSubview(circleView)
                    
                    // Create hosting controller for CapsuleLabel
                    let hosting = UIHostingController(rootView: CapsuleLabel(text: nameText))
                    hosting.view.backgroundColor = .clear
                    let labelSize = hosting.sizeThatFits(in: CGSize(width: 280, height: CGFloat.greatestFiniteMagnitude))
                    let labelWidth = min(280, labelSize.width)
                    let labelHeight = labelSize.height
                    let labelX = (container.bounds.width - labelWidth)/2
                    let labelY = iconDiameter + spacing
                    hosting.view.frame = CGRect(x: labelX, y: labelY, width: labelWidth, height: labelHeight)
                    hosting.view.tag = 1002
                    container.addSubview(hosting.view)
                    
                    let newWidth = max(iconDiameter, labelWidth)
                    let newHeight = iconDiameter + spacing + labelHeight
                    container.frame = CGRect(x: 0, y: 0, width: newWidth, height: newHeight)
                    
                    annotationView?.addSubview(container)
                    annotationView?.frame = container.frame
                    annotationView?.centerOffset = CGPoint(x: 0, y: -(container.frame.height / 2))
                } else {
                    annotationView?.annotation = poiAnnotation
                    
                    if let container = annotationView?.subviews.first {
                        // Remove previous label view if present
                        if let oldLabelView = container.viewWithTag(1002) {
                            oldLabelView.removeFromSuperview()
                        }
                        // Create a fresh hosting controller for the updated text
                        let hosting = UIHostingController(rootView: CapsuleLabel(text: nameText))
                        hosting.view.backgroundColor = .clear
                        let size = hosting.sizeThatFits(in: CGSize(width: 280, height: CGFloat.greatestFiniteMagnitude))
                        let w = min(280, size.width)
                        let h = size.height
                        let x = (container.bounds.width - w)/2
                        let y = iconDiameter + spacing
                        hosting.view.frame = CGRect(x: x, y: y, width: w, height: h)
                        hosting.view.tag = 1002
                        container.addSubview(hosting.view)
                        // Update container
                        let cw = max(iconDiameter, w)
                        let ch = iconDiameter + spacing + h
                        container.frame = CGRect(x: 0, y: 0, width: cw, height: ch)
                        annotationView?.frame = container.frame
                        annotationView?.centerOffset = CGPoint(x: 0, y: -(container.frame.height / 2))
                        
                        // Update circle view only
                        if let circle = container.viewWithTag(1001) {
                            circle.backgroundColor = UIColor.systemRed
                            if let imageView = circle.subviews.first as? UIImageView {
                                let config = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
                                imageView.image = UIImage(systemName: "mappin.and.ellipse", withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal)
                            }
                        }
                    }
                }
                return annotationView
            }
            
            // Default pin for others (e.g. POIs fallback)
            if let mkAnnotation = annotation as? MKPointAnnotation {
                let id = "DefaultPin"
                var pinView = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKPinAnnotationView
                if pinView == nil {
                    pinView = MKPinAnnotationView(annotation: mkAnnotation, reuseIdentifier: id)
                    pinView?.canShowCallout = true
                    pinView?.animatesDrop = false
                    pinView?.pinTintColor = .red
                } else {
                    pinView?.annotation = mkAnnotation
                }
                return pinView
            }
            
            return nil
        }
        
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            // Detect if region change caused by user gesture
            let view = mapView.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView
            let isUserGesture = view?.isDragging == true || view?.isDecelerating == true || view?.isZooming == true
            
            if isUserGesture {
                parent.onUserInteraction?()
            }
        }
    }
}

struct RouteInfoOverlay: View {
    @ObservedObject var locationManager: LocationManager
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "figure.hiking")
                    .foregroundColor(.green)
                
                Text("Tracking Route")
                    .font(.headline)
                    .foregroundColor(.green)
                
                Spacer()
                
                Text("\(locationManager.currentRoute.count) points")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let startTime = locationManager.routeStartTime {
                HStack {
                    Text("Duration: \(formatDuration(from: startTime))")
                        .font(.subheadline)
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.systemBackground).opacity(0.9))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private func formatDuration(from startTime: Date) -> String {
        let duration = Date().timeIntervalSince(startTime)
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        
        if hours > 0 {
            return String(format: "%d:%02d", hours, minutes)
        } else {
            return String(format: "%d min", minutes)
        }
    }
}

struct POIAnnotationView: View {
    let poi: PointOfInterest
    @State private var showingDetails = false
    
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(.blue)
                .clipShape(Circle())
                .onTapGesture {
                    showingDetails = true
                }
            
            Text(poi.name)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
        .sheet(isPresented: $showingDetails) {
            POIDetailsView(poi: poi)
        }
    }
}

struct POIDetailsView: View {
    let poi: PointOfInterest
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title)
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading) {
                        Text(poi.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(poi.category)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                
                if !poi.description.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description")
                            .font(.headline)
                        
                        Text(poi.description)
                            .font(.body)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Location Details")
                        .font(.headline)
                    
                    Group {
                        HStack {
                            Text("Latitude:")
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.6f", poi.coordinate.latitude))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Longitude:")
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.6f", poi.coordinate.longitude))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Altitude:")
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.1f m", poi.coordinate.altitude))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Recorded:")
                                .fontWeight(.medium)
                            Spacer()
                            Text(poi.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Point of Interest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct QuickPOIModal: View {
    let location: CLLocation?
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var poiName: String = ""
    @State private var selectedCategory = ""
    @State private var showingCategoryCustomization = false
    
    private var effectiveLocation: CLLocation? {
        location ?? locationManager.location
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Point of Interest Details") {
                    TextField("Name", text: $poiName)
                        .textInputAutocapitalization(.words)
                    
                    Picker("Category", selection: $selectedCategory) {
                        Text("Select Category").tag("")
                        ForEach(dataManager.customCategories.sorted().map { String(describing: $0) }, id: \.self) { categoryName in
                            Text(categoryName).tag(categoryName)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                Section("Location") {
                    if let loc = effectiveLocation {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Latitude:")
                                    .fontWeight(.medium)
                                Spacer()
                                Text(String(format: "%.6f", loc.coordinate.latitude))
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                Text("Longitude:")
                                    .fontWeight(.medium)
                                Spacer()
                                Text(String(format: "%.6f", loc.coordinate.longitude))
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                Text("Altitude:")
                                    .fontWeight(.medium)
                                Spacer()
                                if loc.verticalAccuracy < 0 {
                                    Text("Unavailable")
                                        .foregroundColor(.secondary)
                                } else {
                                    Text(String(format: "%.1f m", loc.altitude))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    } else {
                        HStack {
                            ProgressView()
                            Text("Acquiring location…")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Button("Customize categories") {
                            showingCategoryCustomization = true
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("Add Quick POI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        savePOI()
                    }
                    .disabled(poiName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedCategory.isEmpty || effectiveLocation == nil)
                }
            }
        }
        .sheet(isPresented: $showingCategoryCustomization) {
            CategoryCustomizationView(dataManager: dataManager)
        }
    }
    
    private func savePOI() {
        guard let loc = effectiveLocation else { return }
        let poi = PointOfInterest(
            name: poiName.trimmingCharacters(in: .whitespacesAndNewlines),
            description: "",
            coordinate: POICoordinate(from: loc),
            timestamp: Date(),
            category: selectedCategory
        )
        
        dataManager.savePOI(poi)
        dismiss()
    }
}

// MARK: - Route Confirmation Modal
struct RouteConfirmationModal: View {
    @ObservedObject var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss
    @Binding var isRouteNameSheetPresented: Bool

    init(locationManager: LocationManager, isRouteNameSheetPresented: Binding<Bool>) {
        self.locationManager = locationManager
        self._isRouteNameSheetPresented = isRouteNameSheetPresented
    }

    private var titleText: String { locationManager.isTracking ? "Route Tracking" : "Start Route Tracking" }
    private var headlineText: String { locationManager.isTracking ? "Route Tracking Active" : "Start Route Tracking" }
    private var bodyText: String {
        if locationManager.isTracking {
            return "Your route is currently being tracked. You can stop tracking at any time."
        } else {
            return "This will begin tracking your hiking route. Your location will be recorded until you stop tracking."
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "figure.hiking")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .padding(.top)
                
                Text(headlineText)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(bodyText)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
                
                VStack(spacing: 12) {
                    if locationManager.isTracking {
                        Button(action: {
                            locationManager.stopRouteTracking()
                            isRouteNameSheetPresented = true
                            dismiss()
                        }) {
                            Text("Stop Route Tracking")
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        Button(action: {
                            if locationManager.isPaused {
                                locationManager.resumeRouteTracking()
                            } else {
                                locationManager.pauseRouteTracking()
                            }
                        }) {
                            Text(locationManager.isPaused ? "Resume" : "Pause")
                                .foregroundColor(locationManager.isPaused ? .white : .blue)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .background(locationManager.isPaused ? Color.blue : Color.blue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Button(action: {
                            locationManager.startRouteTracking()
                            dismiss()
                        }) {
                            Text("Start Tracking")
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
}

struct RouteNamingModal: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    let onSave: (String) -> Void

    @AppStorage("elevationSmoothingEnabled") private var elevationSmoothingEnabled: Bool = true
    @AppStorage("elevationSmoothingWindow") private var elevationSmoothingWindow: Int = 5
    @AppStorage("elevationGainThresholdMeters") private var elevationGainThresholdMeters: Double = 1.0

    var body: some View {
        NavigationView {
            Form {
                Section("Route Name") {
                    TextField("Enter a name", text: $name)
                        .textInputAutocapitalization(.words)
                }
            }
            .navigationTitle("Save Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
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
    
    func computeDistanceMilesAndElevationFeet(from segments: [[[Double]]]) -> (Double, Double) {
        var totalMeters: Double = 0
        var totalAscentMeters: Double = 0
        
        for seg in segments {
            guard seg.count > 1 else { continue }
            // Extract elevations with fallback to 0.0
            let elevations = seg.map { $0.count > 2 ? $0[2] : 0.0 }
            var smoothedElevations = elevations
            
            if elevationSmoothingEnabled && elevationSmoothingWindow >= 3 {
                let window = elevationSmoothingWindow % 2 == 1 ? elevationSmoothingWindow : elevationSmoothingWindow + 1
                smoothedElevations = smoothElevations(elevations, window: window)
            }
            
            for i in 1..<seg.count {
                let prev = seg[i - 1]
                let curr = seg[i]
                let p1 = CLLocation(latitude: prev[1], longitude: prev[0])
                let p2 = CLLocation(latitude: curr[1], longitude: curr[0])
                totalMeters += p1.distance(from: p2)
                
                let deltaElev = smoothedElevations[i] - smoothedElevations[i - 1]
                if deltaElev > elevationGainThresholdMeters {
                    totalAscentMeters += deltaElev
                }
            }
        }
        
        let miles = totalMeters / 1609.344
        let feet = totalAscentMeters * 3.28084
        return (miles, feet)
    }
}

//#Preview {
struct MapView_Previews: PreviewProvider {
    static var previews: some View {
        MapView(
            locationManager: LocationManager(),
            dataManager: DataManager()
        )
    }
}
