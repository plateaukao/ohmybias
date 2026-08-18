import Foundation
import AVFoundation
import AppKit

final class SoundManager {
    static let shared = SoundManager()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var volume: Float = 0.8 {
        didSet { player.volume = volume }
    }
    private let appSupportSoundsDir: URL

    private init() {
        appSupportSoundsDir = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                            in: .userDomainMask,
                                                            appropriateFor: nil,
                                                            create: true))?.appendingPathComponent("OhMyBias/sounds", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: appSupportSoundsDir, withIntermediateDirectories: true)
        } catch {
            // ignore
        }

        engine.attach(player)
        let mainMixer = engine.mainMixerNode
        engine.connect(player, to: mainMixer, format: nil)
        player.volume = volume

        do {
            try engine.start()
        } catch {
            // If engine can't start, we'll fallback to AVAudioPlayer in loadSound
            debugPrint("SoundManager: engine failed to start: \(error)")
        }

        loadDefaultSoundsIfNeeded()
    }

    private func loadDefaultSoundsIfNeeded() {
        // Try to load click.wav and delete.wav from bundle if present
        if let keyURL = Bundle.main.url(forResource: "click1", withExtension: "wav") {
            try? loadSound(id: "key", url: keyURL)
        }
        if let delURL = Bundle.main.url(forResource: "delete1", withExtension: "wav") {
            try? loadSound(id: "delete", url: delURL)
        }
    }

    func setVolume(_ v: Float) {
        volume = v
    }

    func loadUserSound(id: String = "key", url: URL) throws {
        let dest = appSupportSoundsDir.appendingPathComponent(url.lastPathComponent)
        if !FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.copyItem(at: url, to: dest)
        }
        try loadSound(id: id, url: dest)
        UserDefaults.standard.set(dest.path, forKey: "keySoundFile")
    }

    func loadSound(id: String, url: URL) throws {
        // Try AVAudioFile -> AVAudioPCMBuffer
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = UInt32(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        try file.read(into: buffer)
        buffers[id] = buffer
    }

    func play(_ id: String) {
        // Respect secure input: don't play while secure input enabled
        if (IsSecureEventInputEnabled() as Bool) { return }
        guard UserDefaults.standard.bool(forKey: "keySoundEnabled") else { return }
        if let buffer = buffers[id] {
            if !engine.isRunning {
                try? engine.start()
            }
            player.stop()
            player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
            if !player.isPlaying {
                player.play()
            }
        } else {
            // fallback: try AVAudioPlayer
            if let path = UserDefaults.standard.string(forKey: "keySoundFile") {
                let url = URL(fileURLWithPath: path)
                DispatchQueue.global(qos: .background).async {
                    _ = try? AVAudioPlayer(contentsOf: url).play()
                }
            }
        }
    }
}
