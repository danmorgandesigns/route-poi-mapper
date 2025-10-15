import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("routePrecisionMeters") private var routePrecisionMeters: Double = 5.0
    @AppStorage("updateFrequencyMeters") private var updateFrequencyMeters: Double = 10.0

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
