import SwiftUI

struct ColorInspectorView: View {
    @Binding var brightness: Double
    @Binding var contrast: Double
    @Binding var saturation: Double
    @Binding var temperature: Double
    @Binding var tint: Double
    
    var body: some View {
        Form {
            Section("Global") {
                SliderRow(title: "Brightness", value: $brightness, range: -1...1)
                SliderRow(title: "Contrast", value: $contrast, range: 0...2)
                SliderRow(title: "Saturation", value: $saturation, range: 0...2)
            }
            Section("Temperature/Tint") {
                SliderRow(title: "Temperature", value: $temperature, range: -1...1)
                SliderRow(title: "Tint", value: $tint, range: -1...1)
            }
        }
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var body: some View {
        HStack {
            Text(title)
            Slider(value: $value, in: range)
            Text(String(format: "%.2f", value)).frame(width: 60, alignment: .trailing)
        }
    }
}


