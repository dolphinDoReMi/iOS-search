import SwiftUI
import AVFoundation

struct CaptionsEditorView: View {
    @Binding var captions: [CaptionLine]
    @Binding var currentTime: CMTime
    @State private var filterText: String = ""
    @State private var selectedLang: String? = nil
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Search caption text", text: $filterText)
                Menu(selectedLang ?? "All Languages") {
                    Button("All Languages") { selectedLang = nil }
                    ForEach(Array(Set(captions.map { $0.languageCode })).sorted(), id: \.self) { lang in
                        Button(lang) { selectedLang = lang }
                    }
                }
            }
            .padding(.horizontal)
            
            Table(filtered) {
                TableColumn("Caption Text") { line in
                    TextField("Text", text: binding(for: line).text)
                }
                TableColumn("Start Time") { line in
                    TimeField(time: binding(for: line).start)
                }
                TableColumn("End Time") { line in
                    TimeField(time: binding(for: line).end)
                }
                TableColumn("Lang", value: \.languageCode)
            }
            .frame(minHeight: 160)
            
            HStack {
                Button("+ Add Caption at Playhead") {
                    let start = currentTime
                    let end = CMTimeAdd(start, CMTime(seconds: 2, preferredTimescale: 600))
                    captions.append(CaptionLine(languageCode: selectedLang ?? "en", start: start, end: end, text: ""))
                }
                Spacer()
                Text("\(filtered.count) items")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
    }
    
    private var filtered: [CaptionLine] {
        captions.filter { line in
            (selectedLang == nil || line.languageCode == selectedLang) &&
            (filterText.isEmpty || line.text.localizedCaseInsensitiveContains(filterText))
        }
        .sorted { $0.start.seconds < $1.start.seconds }
    }
    
    private func binding(for line: CaptionLine) -> Binding<CaptionLine> {
        guard let idx = captions.firstIndex(where: { $0.id == line.id }) else {
            return .constant(line)
        }
        return $captions[idx]
    }
}

private struct TimeField: View {
    @Binding var time: CMTime
    @State private var secondsString: String = ""
    
    var body: some View {
        TextField("0.0", text: binding)
            .onAppear { secondsString = String(format: "%.2f", time.seconds) }
    }
    private var binding: Binding<String> {
        Binding<String>(
            get: { String(format: "%.2f", time.seconds) },
            set: { newValue in
                if let s = Double(newValue) {
                    time = CMTime(seconds: s, preferredTimescale: 600)
                }
            }
        )
    }
}


