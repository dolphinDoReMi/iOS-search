import SwiftUI

struct ScopesView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, .gray.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                Text("Scopes (Waveform · Vectorscope · Parade)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [4,4]))
                    .overlay(
                        Text("Waveform placeholder")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    )
            }
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}


