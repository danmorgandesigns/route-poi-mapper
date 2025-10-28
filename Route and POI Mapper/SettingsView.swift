import SwiftUI

struct SettingsView: View {
    @ObservedObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("routePrecisionMeters") private var routePrecisionMeters: Double = 5.0
    @AppStorage("updateFrequencyMeters") private var updateFrequencyMeters: Double = 10.0
    @AppStorage("elevationSmoothingEnabled") private var elevationSmoothingEnabled: Bool = true
    @AppStorage("elevationSmoothingWindow") private var elevationSmoothingWindow: Int = 7
    @AppStorage("elevationGainThresholdMeters") private var elevationGainThresholdMeters: Double = 0.5
    
    @State private var showingCategoryCustomization = false

    enum UnitsSystem: String, CaseIterable, Identifiable {
        case imperial = "imperial"
        case metric = "metric"
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .imperial: return "Imperial"
            case .metric: return "Metric"
            }
        }
        var subtitle: String {
            switch self {
            case .imperial: return "miles & feet"
            case .metric: return "kilometers & meters"
            }
        }
    }
    
    @AppStorage("unitsSystem") private var unitsSystemRaw: String = UnitsSystem.imperial.rawValue
    private var unitsSystem: UnitsSystem {
        get { UnitsSystem(rawValue: unitsSystemRaw) ?? .imperial }
        set { unitsSystemRaw = newValue.rawValue }
    }
    
    private static let defaultRoutePrecisionMeters: Double = 5.0
    private static let defaultUpdateFrequencyMeters: Double = 10.0
    private static let defaultElevationSmoothingWindow: Int = 7
    private static let defaultElevationGainThresholdMeters: Double = 0.5
    
    private func resetToDefaults() {
        routePrecisionMeters = SettingsView.defaultRoutePrecisionMeters
        updateFrequencyMeters = SettingsView.defaultUpdateFrequencyMeters
        elevationSmoothingEnabled = true
        elevationSmoothingWindow = SettingsView.defaultElevationSmoothingWindow
        elevationGainThresholdMeters = SettingsView.defaultElevationGainThresholdMeters
    }

    var body: some View {
        NavigationView {
            Form {
                Section(footer: Text("Manage categories for organizing your Points of Interest.")) {
                    Button(action: {
                        showingCategoryCustomization = true
                    }) {
                        Text("Customize Categories")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .listRowBackground(Color.clear)
                }
                
                Section(footer: Text("Minimum spacing between points in your saved route geometry. Larger values reduce file size but may look less smooth.")) {
                    HStack {
                        Text("Route Precision")
                            .font(.headline)
                        Spacer()
                        Text("\(Int(routePrecisionMeters)) m")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $routePrecisionMeters, in: 2...20, step: 1)
                }
                
                Section(footer: Text("Minimum movement before a new location update is delivered while tracking. Lower values can increase battery usage.")) {
                    HStack {
                        Text("Update Frequency")
                            .font(.headline)
                        Spacer()
                        Text("\(Int(updateFrequencyMeters)) m")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $updateFrequencyMeters, in: 2...50, step: 1)
                }
                
                Section(header: Text("Elevation")) {
                    Toggle("Elevation Smoothing", isOn: $elevationSmoothingEnabled)
                    
                    HStack {
                        Text("Smoothing Window")
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(elevationSmoothingWindow)")
                            .foregroundColor(.secondary)
                        Stepper("", value: $elevationSmoothingWindow, in: 3...9, step: 1)
                            .onChange(of: elevationSmoothingWindow) { newValue in
                                var value = newValue
                                if value < 3 {
                                    value = 3
                                } else if value > 9 {
                                    value = 9
                                }
                                if value % 2 == 0 {
                                    value += 1
                                    if value > 9 {
                                        value = 9
                                    }
                                }
                                if value != elevationSmoothingWindow {
                                    elevationSmoothingWindow = value
                                }
                            }
                    }
                    Text("Controls the size of the window used to smooth elevation data. Larger windows provide smoother results but may delay changes.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("Ascent Threshold")
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(Int(elevationGainThresholdMeters)) m")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $elevationGainThresholdMeters, in: 0.0...5.0, step: 0.1)
                    Text("Minimum elevation gain required to count as ascent. Higher values (2-3m) help filter out GPS noise for more accurate elevation calculations.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    Button(action: { resetToDefaults() }) {
                        Text("Reset to Defaults")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                }
                
                Section(header: Text("Units")) {
                    Picker("Units", selection: $unitsSystemRaw) {
                        Text("Imperial").tag(UnitsSystem.imperial.rawValue)
                        Text("Metric").tag(UnitsSystem.metric.rawValue)
                    }
                    .pickerStyle(.segmented)
                    
                    HStack {
                        Text(unitsSystem.displayName)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(unitsSystem.subtitle)
                            .foregroundColor(.secondary)
                    }
                    .font(.footnote)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .sheet(isPresented: $showingCategoryCustomization) {
            CategoryCustomizationView(dataManager: dataManager)
        }
    }
}

#Preview {
    SettingsView(dataManager: DataManager())
}
