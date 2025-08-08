import Foundation
import AVFoundation

final class FCPXMLExportService {
    enum FCPXError: Error { case failedToWrite }
    
    func exportFCPXML(project: VideoProject) async throws -> URL {
        let xml = buildFCPXML(project: project)
        let url = makeOutputURL()
        try xml.data(using: .utf8)?.write(to: url)
        return url
    }
    
    private func makeOutputURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let name = "storycut_timeline_\(Int(Date().timeIntervalSince1970)).fcpxml"
        return docs.appendingPathComponent(name)
    }
    
    // Minimal FCPXML 1.9 sequence with asset-clip references
    private func buildFCPXML(project: VideoProject) -> String {
        var resources: [String] = []
        var sequenceItems: [String] = []
        
        for (index, clip) in project.clips.enumerated() {
            let refId = "r\(index+1)"
            let assetResource = fcpxResource(for: clip, refId: refId)
            resources.append(assetResource)
            let item = fcpxSequenceItem(for: clip, refId: refId)
            sequenceItems.append(item)
        }
        
        let resourcesXML = resources.joined(separator: "\n")
        let sequenceXML = sequenceItems.joined(separator: "\n")
        
        // Duration is sum of visible duration of clips
        let totalDurationFrames = Int(round(project.totalDuration.seconds * 30.0))
        let durationString = "\(totalDurationFrames)/30s"
        
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.9">
          <resources>
            <format id="r0" name="StoryCut-9x16-1080p30" frameDuration="1/30s" width="1080" height="1920"/>
            \(resourcesXML)
          </resources>
          <library>
            <event name="StoryCut Import">
              <project name="\(project.name)">
                <sequence duration="\(durationString)" format="r0">
                  <spine>
                    \(sequenceXML)
                  </spine>
                </sequence>
              </project>
            </event>
          </library>
        </fcpxml>
        """
        return xml
    }
    
    private func fcpxResource(for clip: EditableClip, refId: String) -> String {
        let path = clip.videoURL.path
        let src = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return "<asset id=\"\(refId)\" name=\"\(clip.videoURL.lastPathComponent)\" start=\"0s\" hasVideo=\"1\" hasAudio=\"1\" format=\"r0\" src=\"file://\(src)\"/>"
    }
    
    private func fcpxSequenceItem(for clip: EditableClip, refId: String) -> String {
        // Map CMTime range to 30fps frames
        let startFrames = Int(round(clip.startTime.seconds * 30.0))
        let durationFrames = Int(round(clip.duration.seconds * 30.0))
        let offsetString = startFrames > 0 ? " offset=\"\(startFrames)/30s\"" : ""
        let durationString = "\(durationFrames)/30s"
        return "<asset-clip ref=\"\(refId)\" name=\"\(clip.videoURL.lastPathComponent)\" duration=\"\(durationString)\"\(offsetString)/>"
    }
}
