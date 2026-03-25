import AppKit
import AVFoundation
import os.log

@MainActor
final class VoiceRecorder {

        private var audioRecorder: AVAudioRecorder?
        private let logger = Logger(subsystem: "hk.eduhk.inputmethod.TypeDuck", category: "VoiceRecorder")

        private static let docsURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

        private static let fileNameFormatter: DateFormatter = {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                return f
        }()

        private static func makeOutputURL() -> URL {
                let name = "typeduck_\(fileNameFormatter.string(from: Date())).wav"
                return docsURL.appendingPathComponent(name)
        }

        var isRecording: Bool {
                audioRecorder?.isRecording ?? false
        }

        func startRecording() {
                guard !isRecording else { return }
                let status = AVCaptureDevice.authorizationStatus(for: .audio)
                switch status {
                case .authorized:
                        beginRecording()
                case .notDetermined:
                        AVCaptureDevice.requestAccess(for: .audio) { granted in
                                Task { @MainActor in
                                        if granted { self.beginRecording() }
                                }
                        }
                default:
                        logger.warning("Microphone access not authorized: \(String(describing: status))")
                }
        }

        private func beginRecording() {
                let outputURL = Self.makeOutputURL()
                let settings: [String: Any] = [
                        AVFormatIDKey: Int(kAudioFormatLinearPCM),
                        AVSampleRateKey: 16000.0,
                        AVNumberOfChannelsKey: 1,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsBigEndianKey: false
                ]
                do {
                        audioRecorder = try AVAudioRecorder(url: outputURL, settings: settings)
                        audioRecorder?.record()
                        NSSound(named: "Tink")?.play()
                        logger.info("Recording started: \(outputURL.lastPathComponent)")
                } catch {
                        logger.error("Failed to start recording: \(error.localizedDescription)")
                }
        }

        func stopRecording() {
                guard let recorder = audioRecorder, recorder.isRecording else { return }
                let path = recorder.url.lastPathComponent
                recorder.stop()
                audioRecorder = nil
                NSSound(named: "Pop")?.play()
                logger.info("Recording stopped, saved: \(path)")
        }
}
