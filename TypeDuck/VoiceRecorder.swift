import AppKit
import AVFoundation
import os.log
import whisper

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

        private let engine = AVAudioEngine()
        private let targetSampleRate: Double = 16000

        func startCapture() throws {
                let input = engine.inputNode
                let inputFormat = input.outputFormat(forBus: 0)
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
                        let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
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
                try engine.start()
        }

        func stopCapture() {
                engine.inputNode.removeTap(onBus: 0)
                engine.stop()
        }
}

// MARK: - Whisper serial queue

private let whisperQueue = DispatchQueue(label: "hk.eduhk.inputmethod.TypeDuck.whisper", qos: .userInitiated)

// MARK: - VoiceRecorder

@MainActor
final class VoiceRecorder {

        /// Called on the main actor when transcription completes. Receives the recognised text.
        var onTranscription: ((String) -> Void)?

        private let capture = AudioCapture()
        private var samples: [Float] = []
        nonisolated(unsafe) private var ctx: OpaquePointer?   // accessed only on whisperQueue
        private let logger = Logger(subsystem: "hk.eduhk.inputmethod.TypeDuck", category: "VoiceRecorder")

        var isModelLoaded: Bool = false
        var isRecording: Bool = false

        // MARK: Model loading

        /// Load whisper model from a `.mlmodelc` path.
        /// Derives the corresponding GGML `.bin` path (strips `-encoder` suffix, changes extension).
        func loadModel(fromMlmodelc mlmodelcPath: String) {
                guard let binPath = Self.binPath(from: mlmodelcPath) else {
                        logger.warning("Cannot derive .bin path from: \(mlmodelcPath)")
                        isModelLoaded = false
                        Self.postLoadState(.failed)
                        return
                }
                isModelLoaded = false
                Self.postLoadState(.loading)
                logger.info("Loading whisper model: \(binPath)")
                // Capture and clear ctx before dispatching to prevent double-free if loadModel is called twice
                let oldCtx = ctx
                ctx = nil
                whisperQueue.async { [weak self] in
                        if let old = oldCtx { whisper_free(old) }
                        let newCtx = whisper_init_from_file(binPath)
                        DispatchQueue.main.async {
                                self?.ctx = newCtx
                                if newCtx != nil {
                                        self?.isModelLoaded = true
                                        self?.logger.info("Whisper model loaded successfully")
                                        Self.postLoadState(.loaded)
                                } else {
                                        self?.logger.error("Whisper model load failed for: \(binPath)")
                                        Self.postLoadState(.failed)
                                }
                        }
                }
        }

        private static func postLoadState(_ state: WhisperModelLoadState) {
                AppSettings.whisperModelLoadState = state
                NotificationCenter.default.post(
                        name: .whisperModelLoadStateDidChange,
                        object: nil,
                        userInfo: ["state": state.rawValue]
                )
        }

        private static func binPath(from mlmodelcPath: String) -> String? {
                let url = URL(fileURLWithPath: mlmodelcPath)
                guard url.pathExtension == "mlmodelc" else { return nil }
                var name = url.deletingPathExtension().lastPathComponent
                if name.hasSuffix("-encoder") {
                        name = String(name.dropLast("-encoder".count))
                }
                return url.deletingLastPathComponent()
                        .appendingPathComponent(name)
                        .appendingPathExtension("bin")
                        .path
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
                do {
                        try capture.startCapture()
                        isRecording = true
                        NSSound(named: "Tink")?.play()
                        logger.info("Voice capture started")
                } catch {
                        logger.error("Failed to start capture: \(error.localizedDescription)")
                }
        }

        func stopRecording() {
                guard isRecording else { return }
                capture.stopCapture()
                isRecording = false
                NSSound(named: "Pop")?.play()
                let buffer = samples
                samples = []
                guard buffer.count > 8000 else {
                        logger.info("Recording too short (\(buffer.count) samples), skipping transcription")
                        return
                }
                let rms = sqrt(buffer.reduce(0) { $0 + $1 * $1 } / Float(buffer.count))
                guard rms > 0.001 else {
                        logger.info("Audio too quiet (RMS=\(rms)), skipping transcription")
                        return
                }
                logger.info("Transcribing \(buffer.count / 16000) sec of audio, RMS=\(rms)...")
                transcribe(buffer)
        }

        // MARK: Transcription

        private func transcribe(_ buffer: [Float]) {
                whisperQueue.async { [weak self] in
                        guard let self, let ctx = self.ctx else { return }
                        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
                        params.print_progress   = false
                        params.print_special    = false
                        params.print_realtime   = false
                        params.print_timestamps = false
                        params.translate        = false
                        params.detect_language  = false
                        params.n_threads        = Int32(max(1, ProcessInfo.processInfo.processorCount / 2))
                        let result: Int32 = "zh".withCString { langPtr in
                                params.language = langPtr
                                return buffer.withUnsafeBufferPointer { buf in
                                        whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
                                }
                        }
                        var text = ""
                        if result == 0 {
                                let n = whisper_full_n_segments(ctx)
                                for i in 0 ..< n {
                                        let noSpeechProb = whisper_full_get_segment_no_speech_prob(ctx, i)
                                        guard noSpeechProb < 0.6 else { continue }
                                        if let seg = whisper_full_get_segment_text(ctx, i) {
                                                text += String(cString: seg)
                                        }
                                }
                        }
                        let finalText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        DispatchQueue.main.async {
                                self.logger.info("Transcription: \(finalText)")
                                if !finalText.isEmpty {
                                        self.onTranscription?(finalText)
                                }
                        }
                }
        }

        deinit {
                if let ctx {
                        whisperQueue.async { whisper_free(ctx) }
                }
        }
}
