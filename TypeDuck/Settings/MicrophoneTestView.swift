import SwiftUI
import AVFoundation
import CoreAudio

// MARK: - Current input device name (CoreAudio)

private func currentInputDeviceName() -> String {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope:    kAudioObjectPropertyScopeGlobal,
                mElement:  kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &addr, 0, nil, &size, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown
        else { return "未知设备" }

        var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope:    kAudioObjectPropertyScopeGlobal,
                mElement:  kAudioObjectPropertyElementMain
        )
        var nameRef: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(deviceID, &nameAddr, 0, nil,
                                         &nameSize, &nameRef) == noErr
        else { return "未知设备" }
        return nameRef as String
}

// MARK: - Audio capture helper

private final class MicCapture: @unchecked Sendable {

        var onLevel: ((Float) -> Void)?

        let sampleRate: Double = 16000
        private(set) var recordedFileURL: URL?

        private var engine: AVAudioEngine?
        private var audioFile: AVAudioFile?      // written on writeQueue
        private let writeQueue = DispatchQueue(label: "hk.eduhk.inputmethod.TypeDuck.micWrite",
                                               qos: .userInitiated)
        private var configObserver: NSObjectProtocol?
        private var active = false

        // MARK: Start / Stop

        func start() throws {
                active = true
                try startEngine(reuseFile: false)
        }

        private func startEngine(reuseFile: Bool) throws {
                // Tear down previous engine
                configObserver.map { NotificationCenter.default.removeObserver($0) }
                configObserver = nil
                engine?.inputNode.removeTap(onBus: 0)
                engine?.stop()
                engine = nil

                let eng = AVAudioEngine()
                // Disable voice processing (AGC, noise suppression, echo cancellation).
                // macOS may enable it automatically for headphone inputs, causing progressive
                // gain reduction ("越来越小") over the first few seconds.
                if #available(macOS 13.0, *) {
                        try? eng.inputNode.setVoiceProcessingEnabled(false)
                }
                let input = eng.inputNode
                let inputFormat = input.outputFormat(forBus: 0)
                guard inputFormat.sampleRate > 0 else { throw MicCaptureError.invalidFormat }

                guard let targetFormat = AVAudioFormat(
                        commonFormat: .pcmFormatFloat32,
                        sampleRate: sampleRate,
                        channels: 1,
                        interleaved: false
                ) else { throw MicCaptureError.invalidFormat }

                guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
                else { throw MicCaptureError.converterUnavailable }

                let ratio = sampleRate / inputFormat.sampleRate

                // Open / reuse audio file
                if !reuseFile || audioFile == nil {
                        let url = FileManager.default.temporaryDirectory
                                .appendingPathComponent("typeduck_mic_test.caf")
                        try? FileManager.default.removeItem(at: url)
                        audioFile = try AVAudioFile(
                                forWriting: url,
                                settings: targetFormat.settings,
                                commonFormat: .pcmFormatFloat32,
                                interleaved: false
                        )
                        recordedFileURL = url
                }
                let file = audioFile!

                input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                        guard let self else { return }
                        // + 1 guards against rounding when ratio is non-integer
                        let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
                        guard outFrames > 0,
                              let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                                            frameCapacity: outFrames)
                        else { return }

                        var convError: NSError?
                        var consumed = false
                        converter.convert(to: outBuf, error: &convError) { _, status in
                                if consumed { status.pointee = .noDataNow; return nil }
                                status.pointee = .haveData
                                consumed = true
                                return buffer
                        }
                        guard convError == nil, outBuf.frameLength > 0,
                              let data = outBuf.floatChannelData?[0]
                        else { return }

                        // Level (computed on audio thread — lightweight)
                        let n = Int(outBuf.frameLength)
                        var sumSq: Float = 0
                        for i in 0..<n { sumSq += data[i] * data[i] }
                        let rms = sqrt(sumSq / Float(n))
                        let db  = 20 * log10(max(rms, 1e-6))
                        let lvl = Float(max(0.0, min(1.0, (db + 50.0) / 50.0)))

                        // Write to file on dedicated queue (outBuf stays alive via ARC)
                        self.writeQueue.async { try? file.write(from: outBuf) }

                        DispatchQueue.main.async { self.onLevel?(lvl) }
                }

                // Handle Bluetooth HFP / device reconfiguration mid-recording
                configObserver = NotificationCenter.default.addObserver(
                        forName: .AVAudioEngineConfigurationChange,
                        object: eng,
                        queue: nil
                ) { [weak self] _ in
                        guard let self, self.active else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                try? self.startEngine(reuseFile: true)   // keep writing to same file
                        }
                }

                engine = eng
                try eng.start()
        }

        func stop() {
                active = false
                configObserver.map { NotificationCenter.default.removeObserver($0) }
                configObserver = nil
                engine?.inputNode.removeTap(onBus: 0)
                engine?.stop()
                engine = nil
                // Flush all pending writes before closing the file
                writeQueue.sync { [weak self] in self?.audioFile = nil }
        }

        func cleanupFile() {
                if let url = recordedFileURL {
                        try? FileManager.default.removeItem(at: url)
                        recordedFileURL = nil
                }
        }
}

private enum MicCaptureError: Error { case invalidFormat, converterUnavailable }

// MARK: - Controller

@MainActor
private final class MicTestController: ObservableObject {

        enum RecordState: Equatable { case idle, recording, recorded, playing, denied }

        @Published var recordState: RecordState = .idle
        @Published var level: Float = 0

        private let capture = MicCapture()
        private var player: AVAudioPlayer?
        private var playerDelegate: PlayerDelegate?

        // MARK: Recording

        func startRecording() {
                guard recordState == .idle || recordState == .recorded else { return }
                let status = AVCaptureDevice.authorizationStatus(for: .audio)
                switch status {
                case .authorized:
                        beginCapture()
                case .notDetermined:
                        AVCaptureDevice.requestAccess(for: .audio) { granted in
                                Task { @MainActor in
                                        if granted { self.beginCapture() }
                                        else { self.recordState = .denied }
                                }
                        }
                default:
                        recordState = .denied
                }
        }

        private func beginCapture() {
                capture.cleanupFile()
                capture.onLevel = { [weak self] l in self?.level = l }
                do {
                        try capture.start()
                        recordState = .recording
                } catch {
                        capture.onLevel = nil
                }
        }

        func stopRecording() {
                capture.stop()
                capture.onLevel = nil
                level = 0
                if capture.recordedFileURL != nil {
                        recordState = .recorded
                } else {
                        recordState = .idle
                }
        }

        // MARK: Playback

        func startPlayback() {
                guard recordState == .recorded, let url = capture.recordedFileURL else { return }
                do {
                        let p = try AVAudioPlayer(contentsOf: url)
                        let del = PlayerDelegate { [weak self] in self?.recordState = .recorded }
                        p.delegate = del
                        playerDelegate = del
                        p.play()
                        player = p
                        recordState = .playing
                } catch {
                        recordState = .recorded
                }
        }

        func stopPlayback() {
                player?.stop()
                player = nil
                playerDelegate = nil
                recordState = .recorded
        }

        // MARK: Reset

        func reset() {
                player?.stop()
                player = nil
                playerDelegate = nil
                capture.stop()
                capture.onLevel = nil
                capture.cleanupFile()
                level = 0
                recordState = .idle
        }
}

// MARK: - AVAudioPlayerDelegate bridge

private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
        private let completion: () -> Void
        init(_ completion: @escaping () -> Void) { self.completion = completion }
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
                DispatchQueue.main.async { self.completion() }
        }
}

// MARK: - View

struct MicrophoneTestView: View {

        @StateObject private var mic = MicTestController()
        @State private var displayLevel: Float = 0
        @State private var inputDeviceName: String = currentInputDeviceName()

        private let levelTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

        var body: some View {
                VStack(alignment: .leading, spacing: 10) {
                        Text("麦克风测试")
                                .font(.headline)

                        HStack(spacing: 6) {
                                Image(systemName: "mic")
                                        .foregroundStyle(Color.secondary)
                                Text(inputDeviceName)
                                        .foregroundStyle(Color.secondary)
                        }
                        .font(.caption)

                        LevelMeterView(level: displayLevel)
                                .frame(height: 14)

                        HStack(spacing: 10) {
                                switch mic.recordState {
                                case .idle:
                                        Button("开始录音") { mic.startRecording() }
                                case .recording:
                                        Button("停止") { mic.stopRecording() }
                                                .foregroundStyle(Color.red)
                                        HStack(spacing: 5) {
                                                Circle().fill(Color.red).frame(width: 7, height: 7)
                                                Text("录音中…")
                                                        .font(.caption)
                                                        .foregroundStyle(Color.secondary)
                                        }
                                case .recorded:
                                        Button("▶ 回听") { mic.startPlayback() }
                                                .buttonStyle(.borderedProminent)
                                        Button("重新录音") { mic.reset() }
                                case .playing:
                                        Button("■ 停止回听") { mic.stopPlayback() }
                                        Text("播放中…")
                                                .font(.caption)
                                                .foregroundStyle(Color.secondary)
                                case .denied:
                                        Image(systemName: "mic.slash")
                                                .foregroundStyle(Color.red)
                                        Text("麦克风权限被拒绝，请前往「系统设置 → 隐私与安全性 → 麦克风」授权")
                                                .font(.caption)
                                                .foregroundStyle(Color.secondary)
                                        Button("重试") { mic.reset() }
                                }
                                Spacer()
                        }
                }
                .onReceive(levelTimer) { _ in
                        let target: Float = mic.recordState == .recording ? mic.level : 0
                        displayLevel += (target - displayLevel) * 0.35
                        if displayLevel < 0.005 { displayLevel = 0 }
                }
                .onReceive(NotificationCenter.default.publisher(
                        for: AVCaptureDevice.wasConnectedNotification)) { _ in
                        inputDeviceName = currentInputDeviceName()
                }
                .onReceive(NotificationCenter.default.publisher(
                        for: AVCaptureDevice.wasDisconnectedNotification)) { _ in
                        inputDeviceName = currentInputDeviceName()
                }
                .onDisappear { mic.reset() }
        }
}

// MARK: - Level Meter

private struct LevelMeterView: View {

        let level: Float
        private let total = 20

        var body: some View {
                GeometryReader { geo in
                        let gap: CGFloat = 2
                        let segW = (geo.size.width - gap * CGFloat(total - 1)) / CGFloat(total)
                        HStack(spacing: gap) {
                                ForEach(0..<total, id: \.self) { i in
                                        let threshold = Float(i) / Float(total)
                                        RoundedRectangle(cornerRadius: 2)
                                                .fill(color(index: i, lit: level > threshold))
                                                .frame(width: segW)
                                }
                        }
                }
        }

        private func color(index: Int, lit: Bool) -> Color {
                guard lit else { return Color.secondary.opacity(0.2) }
                if index < total * 6 / 10 { return .green }
                if index < total * 8 / 10 { return .yellow }
                return .red
        }
}

#Preview {
        MicrophoneTestView()
                .padding()
                .frame(width: 400)
}
