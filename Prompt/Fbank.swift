import Accelerate
import Foundation

/// Kaldi 兼容的 80 维 fbank 特征提取器（纯 Swift + Accelerate）。
///
/// 严格复刻 `kaldi-native-fbank` 的默认配置（SenseVoice 训练时所用）：
///   samp_freq=16000, frame_length=25ms(400), frame_shift=10ms(160),
///   dither=0, snip_edges=false, num_mel_bins=80,
///   window=povey, remove_dc_offset=true, preemph=0.97,
///   round_to_power_of_two=true → n_fft=512, low=20Hz, high=8000Hz(nyquist),
///   use_power=true, use_log_fbank=true, mel 能量下限=FLT_EPSILON。
///
/// FFT 用未归一化功率谱（与 kaldi 的 srfft 一致），因此 CMVN 统计量能对齐。
final class Fbank {

        static let sampleRate = 16000
        static let frameLength = 400          // 25ms
        static let frameShift = 160           // 10ms
        static let nFFT = 512                 // 400 向上取 2 的幂
        static let numMel = 80
        static let lowFreq: Float = 20
        static let highFreq: Float = 8000     // nyquist
        static let preemph: Float = 0.97
        static let melFloor = Float.ulpOfOne  // 1.1920929e-7 → ln = -15.9424

        private let povey: [Float]            // (400) 窗
        private let melStart: [Int]           // 每个 mel 滤波器起始 fft bin
        private let melWeights: [[Float]]     // 每个 mel 滤波器的三角权重

        // vDSP 实数 FFT
        private let log2n: vDSP_Length
        private let fftSetup: FFTSetup

        init() {
                // Povey 窗：pow(0.5 - 0.5*cos(2πi/(N-1)), 0.85)
                let n = Fbank.frameLength
                var w = [Float](repeating: 0, count: n)
                let a = 2.0 * Float.pi / Float(n - 1)
                for i in 0 ..< n {
                        w[i] = pow(0.5 - 0.5 * cos(a * Float(i)), 0.85)
                }
                povey = w

                // Mel 三角滤波器组
                let numFftBins = Fbank.nFFT / 2                    // 256（不含 nyquist bin）
                let fftBinWidth = Float(Fbank.sampleRate) / Float(Fbank.nFFT)  // 31.25
                func melScale(_ f: Float) -> Float { 1127.0 * log(1.0 + f / 700.0) }
                let melLow = melScale(Fbank.lowFreq)
                let melHigh = melScale(Fbank.highFreq)
                let melDelta = (melHigh - melLow) / Float(Fbank.numMel + 1)

                var starts = [Int](repeating: 0, count: Fbank.numMel)
                var weightsAll = [[Float]](repeating: [], count: Fbank.numMel)
                for bin in 0 ..< Fbank.numMel {
                        let leftMel = melLow + Float(bin) * melDelta
                        let centerMel = melLow + Float(bin + 1) * melDelta
                        let rightMel = melLow + Float(bin + 2) * melDelta
                        var first = -1
                        var ws: [Float] = []
                        for i in 0 ..< numFftBins {
                                let freq = fftBinWidth * Float(i)
                                let mel = melScale(freq)
                                if mel > leftMel && mel < rightMel {
                                        let weight: Float = mel <= centerMel
                                                ? (mel - leftMel) / (centerMel - leftMel)
                                                : (rightMel - mel) / (rightMel - centerMel)
                                        if first < 0 { first = i }
                                        ws.append(weight)
                                } else if first >= 0 {
                                        break   // 三角形是连续区间，越过右端即结束
                                }
                        }
                        starts[bin] = max(0, first)
                        weightsAll[bin] = ws
                }
                melStart = starts
                melWeights = weightsAll

                log2n = vDSP_Length(log2(Float(Fbank.nFFT)))
                fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        }

        deinit { vDSP_destroy_fftsetup(fftSetup) }

        /// snip_edges=false 的帧数：(num_samples + frame_shift/2) / frame_shift
        static func numFrames(_ numSamples: Int) -> Int {
                if numSamples <= 0 { return 0 }
                return (numSamples + frameShift / 2) / frameShift
        }

        /// 输入 16kHz 单声道 float PCM，输出 (numFrames, 80) 的 log-mel。
        func compute(_ wave: [Float]) -> [[Float]] {
                let numSamples = wave.count
                let frames = Fbank.numFrames(numSamples)
                if frames == 0 { return [] }

                var out = [[Float]](repeating: [Float](repeating: 0, count: Fbank.numMel), count: frames)

                // FFT 缓冲
                let half = Fbank.nFFT / 2
                var realp = [Float](repeating: 0, count: half)
                var imagp = [Float](repeating: 0, count: half)
                var timeBuf = [Float](repeating: 0, count: Fbank.nFFT)
                var power = [Float](repeating: 0, count: half)   // 256 bins (0..255)

                let n = Fbank.frameLength
                for f in 0 ..< frames {
                        // snip_edges=false: 帧中点 = f*shift + shift/2，帧起点 = 中点 - length/2
                        let start = f * Fbank.frameShift + Fbank.frameShift / 2 - n / 2

                        // 1. 取 400 样本（越界用镜像反射）
                        var frame = [Float](repeating: 0, count: n)
                        for s in 0 ..< n {
                                var idx = start + s
                                while idx < 0 || idx >= numSamples {
                                        if idx < 0 { idx = -idx - 1 }
                                        else { idx = 2 * numSamples - 1 - idx }
                                }
                                frame[s] = wave[idx]
                        }

                        // 2. 去直流（减去均值）
                        var mean: Float = 0
                        vDSP_meanv(frame, 1, &mean, vDSP_Length(n))
                        var negMean = -mean
                        vDSP_vsadd(frame, 1, &negMean, &frame, 1, vDSP_Length(n))

                        // 3. 预加重（后向）：x[i]-=0.97*x[i-1]；x[0]-=0.97*x[0]
                        var i = n - 1
                        while i > 0 { frame[i] -= Fbank.preemph * frame[i - 1]; i -= 1 }
                        frame[0] -= Fbank.preemph * frame[0]

                        // 4. 加 Povey 窗
                        vDSP_vmul(frame, 1, povey, 1, &frame, 1, vDSP_Length(n))

                        // 5. 零填充到 512
                        for k in 0 ..< Fbank.nFFT { timeBuf[k] = k < n ? frame[k] : 0 }

                        // 6. 实数 FFT（未归一化），求功率谱
                        timeBuf.withUnsafeBufferPointer { tp in
                                tp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { cp in
                                        realp.withUnsafeMutableBufferPointer { rp in
                                                imagp.withUnsafeMutableBufferPointer { ip in
                                                        var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                                                        vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(half))
                                                        vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                                                }
                                        }
                                }
                        }
                        // vDSP zrip 的输出是数学 FFT 的 2 倍；功率 = (re^2+im^2)/4
                        // realp[0]=2*X[0](DC), imagp[0]=2*X[N/2](nyquist)——nyquist bin 用不到
                        power[0] = realp[0] * realp[0] * 0.25          // DC
                        for k in 1 ..< half {
                                power[k] = (realp[k] * realp[k] + imagp[k] * imagp[k]) * 0.25
                        }

                        // 7. mel 滤波 + floor + log
                        for bin in 0 ..< Fbank.numMel {
                                let s0 = melStart[bin]
                                let ws = melWeights[bin]
                                var energy: Float = 0
                                for j in 0 ..< ws.count {
                                        energy += ws[j] * power[s0 + j]
                                }
                                if energy < Fbank.melFloor { energy = Fbank.melFloor }
                                out[f][bin] = log(energy)
                        }
                }
                return out
        }
}
