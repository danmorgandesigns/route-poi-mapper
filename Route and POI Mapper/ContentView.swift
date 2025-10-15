//
//  ContentView.swift
//  Route and POI Mapper
//
//  Created by Dan Morgan on 10/10/25.
//

import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var dataManager = DataManager()
    
    var body: some View {
        MapView(locationManager: locationManager, dataManager: dataManager)
    }
}

#Preview {
    ContentView()
}

