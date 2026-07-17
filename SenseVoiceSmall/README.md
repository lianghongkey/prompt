# SenseVoiceSmall → Core ML (.mlmodelc)

把 ModelScope 上的开源 ASR 模型 [`iic/SenseVoiceSmall`](https://www.modelscope.cn/models/iic/SenseVoiceSmall)
一键下载并**源码自转**成一个可在 macOS 端上（走 ANE）推理的 Core ML `.mlmodelc`，
外加 Swift 侧集成所需的全部配套文件。

```bash
cd SenseVoiceSmall
./build_sensevoice_mlmodelc.sh                 # ModelScope 源，输出到 ./dist
# 常用可选项：
./build_sensevoice_mlmodelc.sh --source hf     # 改用 HuggingFace 镜像下载
./build_sensevoice_mlmodelc.sh --output-dir ~/models/sensevoice
./build_sensevoice_mlmodelc.sh --clean         # 重来（清 .build）
./build_sensevoice_mlmodelc.sh -h
```

首次运行会：建虚拟环境、装依赖（torch / coremltools / …，约 3–5GB）、下载模型（约
944MB）、trace + 转换（几分钟）、`coremlcompiler` 编译成 `.mlmodelc`。产物与中间件
全部落在 `.build/` 与 `dist/`（已 `.gitignore`，不会误提交）。

> **已接入 app。** 语音输入现在支持两个引擎，在「设置 → 语音输入 → 识别引擎」里
> 切换 Whisper / SenseVoice。选 SenseVoice 后，把本脚本产出的 `dist/` 目录路径粘进
> 「SenseVoice 模型目录」即可。整条推理链路（fbank/CTC/反查）是**纯 Swift**实现的
> （`Prompt/Fbank.swift` + `Prompt/SenseVoiceEngine.swift`），进程内跑 Core ML，无
> 第三方依赖、无 Python 运行时。详见文末「集成实现」。

转换本身复用已走通 ANE 转换的上游项目
[`madeye/sensevoice-mlx`](https://github.com/madeye/sensevoice-mlx)（可用环境变量
`SENSEVOICE_MLX_REF` 钉住某个 commit）。链路：

```
model.pt --torch.jit.trace--> coremltools(FLOAT16, EnumeratedShapes, iOS17)
         --> SenseVoiceSmall.mlpackage --xcrun coremlcompiler--> SenseVoiceSmall.mlmodelc
```

---

## ⚠️ 关键：这不是 whisper 的 mlmodelc，塞不进现有语音输入

当前 `Prompt/VoiceRecorder.swift` 走的是 **whisper.cpp 的 C API**
（`whisper_init_from_file` 加载 `.bin` GGML 权重）。设置里那个
`ggml-large-v3-turbo-encoder.mlmodelc` 只是 **whisper 专用的 encoder 加速器**，
必须配合同名 `.bin` 一起用——它不是一个独立的 ASR 模型。

SenseVoiceSmall 是**完全不同**的模型：

| | whisper（现状） | SenseVoiceSmall |
|---|---|---|
| 结构 | encoder–decoder，自回归 | **encoder-only + 单个 CTC 头，非自回归** |
| 运行时 | whisper.cpp（GGML） | Core ML（`.mlmodelc`）本身 |
| mlmodelc 角色 | 只是 encoder 的可选加速器 | **就是整个声学模型** |
| 前处理 | whisper.cpp 内部做 mel | **需自己做 fbank+LFR+CMVN+前缀 token** |
| 后处理 | whisper.cpp 内部解码 | **需自己做 CTC 贪心 + SentencePiece 反查** |
| 词表 | whisper tokenizer | SentencePiece BPE（25055 类，含标签 token） |

所以：**产出的 `SenseVoiceSmall.mlmodelc` 无法通过设置里选路径直接用。**
真正接进语音输入，需要新写一条独立的推理链路（见下）。这是本任务之外、单独的
一块 Swift 集成工作。

---

## dist/ 产物清单

| 文件 | 作用 | 用在哪 |
|---|---|---|
| `SenseVoiceSmall.mlmodelc` | Core ML 模型（编码器 + CTC 头） | Core ML `MLModel.prediction` |
| `query_embeddings.npz` | 4 个前缀 query 的 embedding 表 `(16, 560)` | 前处理拼前缀 |
| `am.mvn` | CMVN 均值/方差 | 前处理归一化 |
| `tokens.json` | `id → token 字符串` 词表（25055） | 后处理 |
| `chn_jpn_yue_eng_ko_spectok.bpe.model` | SentencePiece BPE 模型 | 后处理 detokenize |
| `config.yaml` | 网络结构（参考，运行时不必需） | — |

### 模型 I/O 契约（转换后请用 coremltools / Xcode 复核一次）

```
输入  encoder_input : (1, 560, 1, T)   float16   # ANE 布局 (B, C, 1, T)
输出  ctc_logits    : (1, 25055, 1, T) float32
```

`T` 会被 pad 到最近的枚举桶之一：`[21, 38, 54, 88, 171, 254, 338, 504]`
（约 1s–30s + 4 个前缀 token）。**超过 ~30s 的音频这套转换不支持**，需分段。

---

## Swift 侧要复现的完整推理管线

以下前后处理**都在 mlmodelc 之外**（上游 `sensevoice_ane/inference.py` 的 Python
参考实现即是逐步照此做的，移植时对照它最稳）：

**前处理（WAV → encoder_input）**
1. 16kHz 单声道 float PCM（`AudioCapture` 已产出这个格式，可直接复用）。
2. **80 维 Kaldi fbank**：25ms 窗 / 10ms 帧移，`dither=0`，`snip_edges=false`。
   Swift 没有现成实现——可 bridge `kaldi-native-fbank`（C++）或 sherpa-onnx 的
   C API，或自行移植。
3. **LFR**（`lfr_m=7, lfr_n=6`）：帧堆叠 → 560 维。
4. **CMVN**：`feats = (feats + AddShift) * Rescale`，两个向量从 `am.mvn` 解析。
5. **拼 4 个前缀 embedding**（顺序：language, event, emotion, textnorm）：
   - `language`：`auto=0, zh=3, en=4, yue=7, ja=11, ko=12, nospeech=13`
   - `event` = 索引 1，`emotion` = 索引 2（固定）
   - `textnorm`：`withitn=14`（带标点+ITN）/ `woitn=15`
   - embedding 取自 `query_embeddings.npz` 的 `(16, 560)` 表。
   拼成 `(T+4, 560)`。中文输入建议 `language="auto"`（或固定 `zh`）+ `textnorm="withitn"`。
6. **× √512** 缩放。
7. **正弦位置编码**相加（FunASR `SinusoidalPositionEncoder`，`depth=560`：
   `pos=1..len`，`concat(sin, cos)`；`inference.py` 里有精确公式）。
8. pad 到最近的枚举桶长度；reshape 成 `(1, 560, 1, T)`；转 `float16`。

**后处理（ctc_logits → 文本）**
9. `ctc_logits` squeeze→ `(25055, T)`，切到实际长度、转置 → `(len, 25055)`。
10. **CTC 贪心**：`argmax` → 去连续重复 → 去掉 blank（id 0）。
11. **detokenize**：`tokens.json` 映射成 piece，再 `SentencePieceProcessor.decode_pieces`。
12. 用正则 `<\|[^|]+\|>` 剥掉 `<|zh|><|NEUTRAL|><|Speech|><|withitn|>` 等标签，`trim`。
13.（可选）繁→简，接你现有 IME 的转换与纠错。

移植时要引入的新依赖：**Core ML**（系统自带）、**一个 fbank 实现** 和 **一个
SentencePiece 实现**（C++ bridge 或纯 Swift 移植）——这两个是当前工程没有的。

---

## 集成实现（已完成）

做成了**与 whisper 并存的第二引擎**，设置里开关切换，而不是替换：

- `Prompt/Fbank.swift` — Kaldi 兼容 80 维 fbank（Accelerate/vDSP），数值已和参考逐值对齐。
- `Prompt/SenseVoiceEngine.swift` — `public final class SenseVoiceEngine`，输入
  `[Float]`（16k mono）+ 模型目录，输出文本；封装上面整条前后处理 + Core ML predict。
- `Prompt/VoiceRecorder.swift` — 加了 `Backend`（whisper / senseVoice）。`reload()` 按
  `AppSettings.voiceEngine` 加载所选引擎；`transcribe()` 路由到对应后端。复用了原有
  `AudioCapture`、录音生命周期、RMS/时长过滤、`onTranscription` 回调，`PromptInputController`
  几乎无改动。
- `AppSettings` 新增 `voiceEngine` 与 `senseVoiceModelDir`（持久化）；`VoiceSettingsView`
  新增引擎分段选择器 + 模型目录输入框。

**用法**：设置 → 语音输入 → 识别引擎选 **SenseVoice** → 「SenseVoice 模型目录」填
`dist/` 路径 → 应用。之后和以前一样：待机（中文模式）时 **Shift+Space** 开始录音，
松开结束、插入识别文本。语音纠错（LLM）等下游流程照旧生效。

**离线验证工具**：`SenseVoiceKit/`（SwiftPM，源码用符号链接指向上面两个 app 文件，
单一真源）。`swift run sensevoice-cli <dist> <16k.wav>` 可直接跑识别，用于回归。

**已知边界**：此转换最长约 30s（枚举 shape 上限 504 帧）；更长音频当前会被截断，语音
输入的短句场景不受影响。SenseVoice 无 whisper 的 no-speech-prob，幻觉过滤沿用录音端
的 RMS + 时长阈值。

### 更省事的替代路径（如果不追求 ANE）

- **sherpa-onnx**：官方带 **Swift / macOS** 封装，fbank 前处理、CTC 后处理、
  SentencePiece 全部封好，`model.int8.onnx`（约 229MB）+ `tokens.txt` 即可跑。
  最快能跑起来，代价是走 ONNX Runtime 而非 ANE。
- **sensevoice.cpp**（ggml / GGUF，约 254MB q8）：和本工程现有的
  `whisper.framework` / `llama.framework` 的 ggml 生态最统一，内置 FSMN-VAD，
  运行时零 Python。

上面这两条不产出 `.mlmodelc`，但如果目标是"尽快把 SenseVoice 接进语音输入"，
它们比自己复现整条 Core ML 管线省事得多。本目录的脚本满足的是"要 mlmodelc + ANE"
这一具体诉求。

---

## 依赖与耗时

- macOS + Xcode（`xcrun coremlcompiler`）；Apple Silicon 用于 ANE 验证/运行。
- Python 3.10–3.12；脚本自建 venv，装 `torch / coremltools / kaldi-native-fbank /
  sentencepiece / onnxruntime / soundfile / huggingface_hub`（+ `modelscope`）。
- 磁盘：模型约 944MB，环境约 3–5GB，`.mlpackage` 约 448MB。
- 转换耗时：分钟级（编码器不大）；首次装依赖 + 下载才是大头。

## 参考

- 模型：<https://www.modelscope.cn/models/iic/SenseVoiceSmall> ·
  HF 镜像 <https://huggingface.co/FunAudioLLM/SenseVoiceSmall>
- 转换脚本上游：<https://github.com/madeye/sensevoice-mlx>
- 已编译成品（本脚本未用，仅参考）：<https://huggingface.co/FluidInference/sensevoice-small-coreml>
- 替代部署：<https://github.com/lovemefan/SenseVoice.cpp> ·
  <https://k2-fsa.github.io/sherpa/onnx/sense-voice/index.html>
