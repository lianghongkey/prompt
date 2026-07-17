import AVFoundation
import Foundation
import SenseVoiceKit

// 用法：
//   sensevoice-cli <modelDir> <wav> [--debug-cmvn]
//   sensevoice-cli <modelDir> <wav> --lang zh --textnorm withitn

func die(_ msg: String) -> Never {
        FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
        exit(1)
}

let args = CommandLine.arguments
guard args.count >= 3 else {
        die("用法: sensevoice-cli <modelDir> <wav> [--debug-cmvn] [--lang auto|zh] [--textnorm withitn|woitn]")
}
let modelDir = URL(fileURLWithPath: args[1])
let wavPath = URL(fileURLWithPath: args[2])
let debugCMVN = args.contains("--debug-cmvn")
var lang: SenseVoiceEngine.Language = .auto
var textnorm: SenseVoiceEngine.TextNorm = .withITN
if let i = args.firstIndex(of: "--lang"), i + 1 < args.count {
        lang = args[i + 1] == "zh" ? .zh : .auto
}
if let i = args.firstIndex(of: "--textnorm"), i + 1 < args.count {
        textnorm = args[i + 1] == "woitn" ? .withoutITN : .withITN
}

/// 读 wav → 16kHz 单声道 [Float]（必要时重采样/下混）。
func loadPCM16k(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)
        else { die("无法创建目标格式") }

        let cap = AVAudioFrameCount(file.length)
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: cap) else { die("无法分配缓冲") }
        try file.read(into: inBuf)

        if inFormat.sampleRate == 16000 && inFormat.channelCount == 1 {
                let p = inBuf.floatChannelData![0]
                return Array(UnsafeBufferPointer(start: p, count: Int(inBuf.frameLength)))
        }
        // 重采样 / 下混
        guard let conv = AVAudioConverter(from: inFormat, to: target) else { die("无法创建转换器") }
        let ratio = 16000.0 / inFormat.sampleRate
        let outCap = AVAudioFrameCount(Double(inBuf.frameLength) * ratio) + 1024
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outCap) else { die("无法分配输出缓冲") }
        var fed = false
        var err: NSError?
        conv.convert(to: outBuf, error: &err) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true; status.pointee = .haveData; return inBuf
        }
        if let err { die("重采样失败: \(err)") }
        let p = outBuf.floatChannelData![0]
        return Array(UnsafeBufferPointer(start: p, count: Int(outBuf.frameLength)))
}

do {
        let samples = try loadPCM16k(wavPath)
        FileHandle.standardError.write("samples=\(samples.count) (\(samples.count / 16000)s)\n".data(using: .utf8)!)
        let engine = try SenseVoiceEngine(modelDir: modelDir)

        if debugCMVN {
                let feats = engine.debugCMVNFeatures(samples)
                func row(_ i: Int) -> String {
                        guard i < feats.count else { return "-" }
                        return feats[i].prefix(6).map { String(format: "%.5f", $0) }.joined(separator: " ")
                }
                print("CMVN shape: \(feats.count) x \(feats.first?.count ?? 0)")
                print("cmvn[0,:6] \(row(0))")
                print("cmvn[1,:6] \(row(1))")
                print("cmvn[10,:6] \(row(10))")
                print("参考       [-3.77821 -3.79155 -3.90372 -4.00612 -4.08966 -4.14396] (row0)")
        }

        let t0 = Date()
        let text = try engine.transcribe(samples: samples, language: lang, textnorm: textnorm)
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        FileHandle.standardError.write("推理耗时 \(ms)ms\n".data(using: .utf8)!)
        print(text)
} catch {
        die("错误: \(error.localizedDescription)")
}
