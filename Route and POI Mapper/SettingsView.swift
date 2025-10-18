import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("routePrecisionMeters") private var routePrecisionMeters: Double = 5.0
    @AppStorage("updateFrequencyMeters") private var updateFrequencyMeters: Double = 10.0
    
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
    
    private func resetToDefaults() {
        routePrecisionMeters = SettingsView.defaultRoutePrecisionMeters
        updateFrequencyMeters = SettingsView.defaultUpdateFrequencyMeters
    }

    var body: some View {
        NavigationView {
            Form {
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
    }
}

#Preview {
    SettingsView()
}
