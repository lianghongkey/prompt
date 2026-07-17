import AppKit
import AVFoundation
import CoreAudio
import os.log

// MARK: - AudioCapture (16kHz mono Float32 PCM via AVAudioEngine)

private final class AudioCapture: @unchecked Sendable {

        enum CaptureError: Error, LocalizedError {
                case formatUnavailable
                case converterUnavailable
                var errorDescription: String? {
                        switch self {
                        case .formatUnavailable:    return "无法创建音频格式"
                        case .converterUnavailable: return "无法创建采样率转换器"
                        }
                }
        }

        var onSamples: (([Float]) -> Void)?
        var onReconfigure: (() -> Void)?

        private var engine: AVAudioEngine?
        private var configObserver: NSObjectProtocol?
        private let targetSampleRate: Double = 16000
        private var active = false
        private let logger = Logger(subsystem: "hk.eduhk.inputmethod.Prompt", category: "AudioCapture")

        func startCapture() throws {
                active = true
                try attachEngine()
        }

        private func attachEngine(fromConfigChange: Bool = false) throws {
                configObserver.map { NotificationCenter.default.removeObserver($0) }
                configObserver = nil
                if !fromConfigChange {
                        // Safe to remove tap normally. Skip this on config-change restarts:
                        // after AVAudioEngineConfigurationChange the input node has been
                        // reconfigured and calling removeTap on it can leave the audio
                        // subsystem in a bad state that prevents future recording.
                        engine?.inputNode.removeTap(onBus: 0)
                }
                engine?.stop()
                engine = nil

                let eng = AVAudioEngine()
                if #available(macOS 13.0, *) {
                        try? eng.inputNode.setVoiceProcessingEnabled(false)
                }

                // Register for config change BEFORE start so we catch any immediate reconfiguration.
                configObserver = NotificationCenter.default.addObserver(
                        forName: .AVAudioEngineConfigurationChange,
                        object: eng,
                        queue: nil
                ) { [weak self] _ in
                        guard let self, self.active else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                // Discard samples collected during the HFP transition —
                                // they were captured with the pre-switch format and are corrupt.
                                self.onReconfigure?()
                                try? self.attachEngine(fromConfigChange: true)
                        }
                }

                engine = eng
                // Start the engine FIRST so inputNode connects to hardware and
                // outputFormat(forBus:) returns the real device format, not a stale
                // default. Querying the format before start can return sampleRate=0
                // or channelCount=0, which makes the converter produce all-zero samples.
                try eng.start()

                let input = eng.inputNode
                let inputFormat = input.outputFormat(forBus: 0)
                logger.debug("AudioCapture inputFormat: sampleRate=\(inputFormat.sampleRate), channels=\(inputFormat.channelCount)")
                guard let convertFormat = AVAudioFormat(
                        commonFormat: .pcmFormatFloat32,
                        sampleRate: targetSampleRate,
                        channels: 1,
                        interleaved: false
                ) else { throw CaptureError.formatUnavailable }
                guard let converter = AVAudioConverter(from: inputFormat, to: convertFormat)
                else { throw CaptureError.converterUnavailable }
                let ratio = targetSampleRate / inputFormat.sampleRate
                input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                        guard let self else { return }
                        // + 1 guards against off-by-one when ratio is non-integer
                        let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
                        guard outFrames > 0,
                              let outBuf = AVAudioPCMBuffer(pcmFormat: convertFormat, frameCapacity: outFrames)
                        else { return }
                        var error: NSError?
                        var consumed = false
                        converter.convert(to: outBuf, error: &error) { _, status in
                                if consumed { status.pointee = .noDataNow; return nil }
                                status.pointee = .haveData
                                consumed = true
                                return buffer
                        }
                        guard error == nil, outBuf.frameLength > 0,
                              let data = outBuf.floatChannelData?[0]
                        else { return }
                        let samples = Array(UnsafeBufferPointer(start: data, count: Int(outBuf.frameLength)))
                        DispatchQueue.main.async { self.onSamples?(samples) }
                }
        }

        func stopCapture() {
                active = false
                configObserver.map { NotificationCenter.default.removeObserver($0) }
                configObserver = nil
                engine?.inputNode.removeTap(onBus: 0)
                engine?.stop()
                engine = nil
        }

        deinit { stopCapture() }
}

// MARK: - Voice serial queue

let voiceQueue = DispatchQueue(label: "hk.eduhk.inputmethod.Prompt.voice", qos: .userInitiated)

// MARK: - VoiceRecorder (SenseVoiceSmall, in-process Core ML)

@MainActor
final class VoiceRecorder {

        /// Called on the main actor when transcription completes. Receives the recognised text.
        var onTranscription: ((String) -> Void)?

        private let capture = AudioCapture()
        private var samples: [Float] = []
        // 只在 voiceQueue / 加载完成的 main 回调里访问。
        nonisolated(unsafe) private var sense: SenseVoiceEngine?
        private let logger = Logger(subsystem: "hk.eduhk.inputmethod.Prompt", category: "VoiceRecorder")
        private let timing = Logger(subsystem: "hk.eduhk.inputmethod.Prompt", category: "Timing")

        var isModelLoaded: Bool = false
        var isModelLoading: Bool = false
        var isRecording: Bool = false

        // MARK: Model loading

        /// 加载 SenseVoiceSmall 模型目录（后台线程，不阻塞 IME）。幂等，供 activate / 设置变更调用。
        func reload() {
                let dir = AppSettings.senseVoiceModelDir
                guard !dir.isEmpty else {
                        isModelLoaded = false
                        isModelLoading = false
                        sense = nil
                        Self.postLoadState(.notConfigured)
                        return
                }
                isModelLoaded = false
                isModelLoading = true
                Self.postLoadState(.loading)
                logger.info("Loading SenseVoice model: \(dir)")
                let url = URL(fileURLWithPath: dir)
                voiceQueue.async { [weak self] in
                        let engine = try? SenseVoiceEngine(modelDir: url)
                        DispatchQueue.main.async {
                                guard let self else { return }
                                self.isModelLoading = false
                                if let engine {
                                        self.sense = engine
                                        self.isModelLoaded = true
                                        self.logger.info("SenseVoice model loaded successfully")
                                        Self.postLoadState(.loaded)
                                } else {
                                        self.sense = nil
                                        self.logger.error("SenseVoice model load failed for: \(dir)")
                                        Self.postLoadState(.failed)
                                }
                        }
                }
        }

        private static func postLoadState(_ state: VoiceModelLoadState) {
                AppSettings.voiceModelLoadState = state
                NotificationCenter.default.post(
                        name: .voiceModelLoadStateDidChange,
                        object: nil,
                        userInfo: ["state": state.rawValue]
                )
        }

        /// Returns true if the current default audio input device is not the built-in mic
        /// (e.g. Bluetooth or USB headphones), in which case playing sounds through it
        /// would trigger Bluetooth HFP mode and degrade recording quality.
        static func isUsingHeadphoneInput() -> Bool {
                var deviceID = AudioDeviceID(0)
                var size = UInt32(MemoryLayout<AudioDeviceID>.size)
                var addr = AudioObjectPropertyAddress(
                        mSelector: kAudioHardwarePropertyDefaultInputDevice,
                        mScope: kAudioObjectPropertyScopeGlobal,
                        mElement: kAudioObjectPropertyElementMain
                )
                guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID) == noErr else { return false }
                var transportType: UInt32 = 0
                size = UInt32(MemoryLayout<UInt32>.size)
                addr.mSelector = kAudioDevicePropertyTransportType
                guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &transportType) == noErr else { return false }
                return transportType != kAudioDeviceTransportTypeBuiltIn
        }

        // MARK: Recording

        func startRecording() {
                guard isModelLoaded, !isRecording else { return }
                let status = AVCaptureDevice.authorizationStatus(for: .audio)
                switch status {
                case .authorized:
                        beginCapture()
                case .notDetermined:
                        AVCaptureDevice.requestAccess(for: .audio) { granted in
                                Task { @MainActor in
                                        if granted { self.beginCapture() }
                                }
                        }
                default:
                        logger.warning("Microphone access not authorized: \(String(describing: status))")
                }
        }

        private func beginCapture() {
                guard !isRecording else { return }
                samples = []
                capture.onSamples = { [weak self] newSamples in
                        self?.samples.append(contentsOf: newSamples)
                }
                capture.onReconfigure = { [weak self] in
                        // Bluetooth HFP switch corrupts audio collected with the pre-switch
                        // format; discard it so only post-reconfiguration audio is transcribed.
                        self?.samples = []
                }
                do {
                        try capture.startCapture()
                        isRecording = true
                        if !Self.isUsingHeadphoneInput() {
                                NSSound(named: "Tink")?.play()
                        }
                        logger.info("Voice capture started")
                } catch {
                        logger.error("Failed to start capture: \(error.localizedDescription)")
                        // Notify so the controller can clear the 🎙 marked text and reset state.
                        onTranscription?("")
                }
        }

        func stopRecording() {
                guard isRecording else { return }
                capture.stopCapture()
                isRecording = false
                if !Self.isUsingHeadphoneInput() {
                        NSSound(named: "Pop")?.play()
                }
                let buffer = samples
                samples = []
                timing.info("T0 stopRecording samples=\(buffer.count) dur_ms=\(buffer.count * 1000 / 16000)")
                guard buffer.count > 8000 else {
                        logger.info("Recording too short (\(buffer.count) samples), skipping transcription")
                        onTranscription?("")
                        return
                }
                let rms = sqrt(buffer.reduce(0) { $0 + $1 * $1 } / Float(buffer.count))
                guard rms > 0.001 else {
                        logger.info("Audio too quiet (RMS=\(rms)), skipping transcription")
                        onTranscription?("")
                        return
                }
                logger.info("Transcribing \(buffer.count / 16000) sec of audio, RMS=\(rms)...")
                transcribe(buffer)
        }

        // MARK: Transcription

        private func transcribe(_ buffer: [Float]) {
                voiceQueue.async { [weak self] in
                        guard let self else { return }
                        guard let sense = self.sense else {
                                DispatchQueue.main.async { self.onTranscription?("") }
                                return
                        }
                        self.timing.info("T1 sensevoice begin")
                        let start = Date()
                        let text = (try? sense.transcribe(samples: buffer)) ?? ""
                        let ms = Int(Date().timeIntervalSince(start) * 1000)
                        let finalText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.timing.info("T2 sensevoice end took_ms=\(ms) text_len=\(finalText.count)")
                        DispatchQueue.main.async {
                                self.logger.info("SenseVoice transcription: \(finalText)")
                                self.onTranscription?(finalText)
                        }
                }
        }
}
