import SwiftUI

struct EffectsBrowserView: View {
    private let effects = [
        "Brightness/Contrast", "Saturation", "Blur", "Sharpen",
        "Vignette", "Color Tint", "Temperature/Tint", "Fade",
        "Crop", "Transform", "LUT"
    ]
    @State private var query: String = ""
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Effects").font(.headline)
                Spacer()
                TextField("Search", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
            }
            .padding(.horizontal)
            
            ScrollView {
                LazyVGrid(columns: Array(repeating: .init(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    ForEach(filtered, id: \.self) { name in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.15))
                            .overlay(Text(name).font(.footnote).padding(8))
                            .frame(height: 60)
                    }
                }
                .padding(8)
            }
        }
    }
    private var filtered: [String] {
        query.isEmpty ? effects : effects.filter { $0.localizedCaseInsensitiveContains(query) }
    }
}


