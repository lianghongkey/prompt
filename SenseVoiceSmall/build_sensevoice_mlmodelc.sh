#!/usr/bin/env bash
#
# build_sensevoice_mlmodelc.sh
#
# 一键：从 ModelScope 下载 iic/SenseVoiceSmall，源码自转成一个可用于端上
# 语音识别的 Core ML `.mlmodelc`（ANE 优化），并把 Swift 侧集成所需的配套
# 文件一并整理到 dist/ 下。
#
#   https://www.modelscope.cn/models/iic/SenseVoiceSmall
#
# 转换本身复用已走通 ANE 转换的上游项目 madeye/sensevoice-mlx：
#   PyTorch(model.pt) --torch.jit.trace--> coremltools(FLOAT16, EnumeratedShapes)
#   --> SenseVoiceSmall.mlpackage --xcrun coremlcompiler--> SenseVoiceSmall.mlmodelc
#
# ⚠️  重要：产出的 mlmodelc 不是 whisper 的 encoder mlmodelc，无法塞进当前
#     VoiceRecorder（whisper.cpp）管线。它需要一套独立的端上推理链路（fbank +
#     LFR + CMVN + 4 前缀 token + Core ML predict + CTC 贪心解码 + SentencePiece
#     反查）。详见同目录 README.md。
#
# 用法：
#   ./build_sensevoice_mlmodelc.sh                 # 默认：ModelScope 源，输出到 ./dist
#   ./build_sensevoice_mlmodelc.sh --source hf     # 改用 HuggingFace 镜像下载
#   ./build_sensevoice_mlmodelc.sh --output-dir ~/models/sensevoice
#   ./build_sensevoice_mlmodelc.sh --skip-download # 复用已下载的权重
#   ./build_sensevoice_mlmodelc.sh --clean         # 先清掉 .build 再重来
#   ./build_sensevoice_mlmodelc.sh -h              # 帮助
#
set -euo pipefail

# ---------------------------------------------------------------------------
# 路径与默认值
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WORK_DIR="${SCRIPT_DIR}/.build"
OUTPUT_DIR="${SCRIPT_DIR}/dist"
SOURCE="modelscope"                        # modelscope | hf
MODELSCOPE_ID="iic/SenseVoiceSmall"
HF_ID="FunAudioLLM/SenseVoiceSmall"
UPSTREAM_REPO="https://github.com/madeye/sensevoice-mlx.git"
UPSTREAM_REF="${SENSEVOICE_MLX_REF:-main}"  # 可用环境变量钉住某个 commit/tag
SKIP_DOWNLOAD=0
DO_CLEAN=0

MODEL_NAME="SenseVoiceSmall"               # 产物基名 → SenseVoiceSmall.mlmodelc

# ---------------------------------------------------------------------------
# 小工具
# ---------------------------------------------------------------------------
log()  { printf '\033[1;34m[build]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ ok ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"; exit 0; }

# ---------------------------------------------------------------------------
# 解析参数
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
        case "$1" in
                --output-dir) OUTPUT_DIR="$2"; shift 2;;
                --work-dir)   WORK_DIR="$2"; shift 2;;
                --source)     SOURCE="$2"; shift 2;;
                --skip-download) SKIP_DOWNLOAD=1; shift;;
                --clean)      DO_CLEAN=1; shift;;
                -h|--help)    usage;;
                *) die "未知参数：$1（用 -h 查看用法）";;
        esac
done

REPO_DIR="${WORK_DIR}/sensevoice-mlx"
VENV_DIR="${WORK_DIR}/venv"
MODEL_CACHE="${REPO_DIR}/model_cache/SenseVoiceSmall"   # madeye 默认查找目录

# ---------------------------------------------------------------------------
# 0. 环境预检
# ---------------------------------------------------------------------------
log "预检环境 …"
[[ "$(uname -s)" == "Darwin" ]] || die "只能在 macOS 上运行（需要 xcrun coremlcompiler）。"
command -v git     >/dev/null || die "缺少 git。"
command -v python3 >/dev/null || die "缺少 python3（需 3.10 / 3.11 / 3.12）。"
xcrun --find coremlcompiler >/dev/null 2>&1 || die "找不到 coremlcompiler，请先装 Xcode 并运行 xcode-select --install。"

PYVER="$(python3 -c 'import sys; print("%d.%d"%sys.version_info[:2])')"
case "$PYVER" in
        3.10|3.11|3.12) ok "python3 = ${PYVER}";;
        *) warn "python3 = ${PYVER}（torch / coremltools 推荐 3.10–3.12，继续但可能装不上轮子）。";;
esac

[[ "$SOURCE" == "modelscope" || "$SOURCE" == "hf" ]] || die "--source 只能是 modelscope 或 hf。"

if [[ "$DO_CLEAN" == "1" ]]; then
        log "清理 ${WORK_DIR} …"
        rm -rf "$WORK_DIR"
fi

mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# 1. 克隆 / 更新上游转换项目
# ---------------------------------------------------------------------------
if [[ -d "${REPO_DIR}/.git" ]]; then
        log "上游仓库已存在，git fetch …"
        git -C "$REPO_DIR" fetch --quiet --depth 1 origin "$UPSTREAM_REF" || warn "fetch 失败，用现有副本。"
        git -C "$REPO_DIR" checkout --quiet FETCH_HEAD 2>/dev/null || true
else
        log "克隆 ${UPSTREAM_REPO}（ref=${UPSTREAM_REF}）…"
        git clone --quiet --depth 1 --branch "$UPSTREAM_REF" "$UPSTREAM_REPO" "$REPO_DIR" \
                || git clone --quiet --depth 1 "$UPSTREAM_REPO" "$REPO_DIR" \
                || die "克隆上游仓库失败。"
fi
ok "上游项目就绪：${REPO_DIR}"

# ---------------------------------------------------------------------------
# 2. 建虚拟环境并装依赖
# ---------------------------------------------------------------------------
if [[ ! -d "$VENV_DIR" ]]; then
        log "创建虚拟环境 …"
        python3 -m venv "$VENV_DIR"
fi
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

log "安装依赖（首次约需几分钟、数 GB）…"
python -m pip install --quiet --upgrade pip
python -m pip install --quiet -r "${REPO_DIR}/requirements.txt"
# 下载源 SDK：ModelScope 用 modelscope，HF 用 huggingface_hub（已在 requirements 里）
if [[ "$SOURCE" == "modelscope" ]]; then
        python -m pip install --quiet "modelscope"
fi
ok "依赖安装完成。"

# ---------------------------------------------------------------------------
# 3. 下载模型权重（含 model.pt / tokens.json / am.mvn / bpe.model / config.yaml）
# ---------------------------------------------------------------------------
mkdir -p "$MODEL_CACHE"
if [[ "$SKIP_DOWNLOAD" == "1" && -f "${MODEL_CACHE}/model.pt" ]]; then
        ok "跳过下载，复用 ${MODEL_CACHE}/model.pt"
elif [[ -f "${MODEL_CACHE}/model.pt" && "$(stat -f%z "${MODEL_CACHE}/model.pt")" -gt 900000000 ]]; then
        ok "已存在完整 model.pt，跳过下载（如需重下请删掉 ${MODEL_CACHE}）。"
else
        log "从 ${SOURCE} 下载模型到 ${MODEL_CACHE} …（约 944MB）"
        if [[ "$SOURCE" == "modelscope" ]]; then
                MS_ID="$MODELSCOPE_ID" DEST="$MODEL_CACHE" python - <<'PY'
import os
from modelscope import snapshot_download
snapshot_download(os.environ["MS_ID"], local_dir=os.environ["DEST"])
print("ModelScope 下载完成")
PY
        else
                HF_ID="$HF_ID" DEST="$MODEL_CACHE" python - <<'PY'
import os
from huggingface_hub import snapshot_download
snapshot_download(os.environ["HF_ID"], local_dir=os.environ["DEST"])
print("HuggingFace 下载完成")
PY
        fi
fi

# 校验关键文件
for f in model.pt tokens.json am.mvn chn_jpn_yue_eng_ko_spectok.bpe.model; do
        [[ -f "${MODEL_CACHE}/${f}" ]] || die "下载缺少必需文件：${f}（在 ${MODEL_CACHE}）。"
done
ok "模型文件齐全。"

# ---------------------------------------------------------------------------
# 4. 源码自转 → .mlpackage（+ query_embeddings.npz）
# ---------------------------------------------------------------------------
MLPACKAGE="${REPO_DIR}/${MODEL_NAME}.mlpackage"
log "转换 PyTorch → Core ML（.mlpackage，约几分钟）…"
( cd "$REPO_DIR" && python -m sensevoice_ane.convert \
        --checkpoint "${MODEL_CACHE}/model.pt" \
        --output "${MLPACKAGE}" )
[[ -d "$MLPACKAGE" ]] || die "转换未产出 ${MLPACKAGE}。"

# query_embeddings.npz：convert 会写到仓库根（CWD）。定位它。
EMB_NPZ=""
for cand in "${REPO_DIR}/query_embeddings.npz" "$(dirname "$MLPACKAGE")/query_embeddings.npz"; do
        [[ -f "$cand" ]] && EMB_NPZ="$cand" && break
done
[[ -n "$EMB_NPZ" ]] || die "找不到 query_embeddings.npz（前缀 embedding 表，端上推理必需）。"
ok "已生成 .mlpackage 与 query_embeddings.npz。"

# ---------------------------------------------------------------------------
# 5. 编译 → .mlmodelc
# ---------------------------------------------------------------------------
log "编译 .mlpackage → .mlmodelc …"
xcrun coremlcompiler compile "$MLPACKAGE" "$OUTPUT_DIR"
MLMODELC="${OUTPUT_DIR}/${MODEL_NAME}.mlmodelc"
[[ -d "$MLMODELC" ]] || die "coremlcompiler 未产出 ${MLMODELC}。"
ok "已编译：${MLMODELC}"

# ---------------------------------------------------------------------------
# 6. 汇总 Swift 侧集成所需的配套文件
# ---------------------------------------------------------------------------
log "整理配套文件到 ${OUTPUT_DIR} …"
cp -f "$EMB_NPZ"                                            "${OUTPUT_DIR}/query_embeddings.npz"
# 导出前缀 embedding 为原始 float32 (16×560)，供 Swift 引擎直接读取（免解析 npz）
EMB_NPZ="$EMB_NPZ" OUTDIR="$OUTPUT_DIR" python - <<'PY'
import os, numpy as np
emb = np.load(os.environ["EMB_NPZ"])["embeddings"].astype("<f4")
emb.tofile(os.path.join(os.environ["OUTDIR"], "query_embeddings.f32"))
print("wrote query_embeddings.f32", emb.size, "floats")
PY
cp -f "${MODEL_CACHE}/am.mvn"                              "${OUTPUT_DIR}/am.mvn"
cp -f "${MODEL_CACHE}/tokens.json"                        "${OUTPUT_DIR}/tokens.json"
cp -f "${MODEL_CACHE}/chn_jpn_yue_eng_ko_spectok.bpe.model" "${OUTPUT_DIR}/chn_jpn_yue_eng_ko_spectok.bpe.model"
cp -f "${MODEL_CACHE}/config.yaml"                        "${OUTPUT_DIR}/config.yaml" 2>/dev/null || true

deactivate || true

# ---------------------------------------------------------------------------
# 完成
# ---------------------------------------------------------------------------
cat <<EOF

$(ok "全部完成。")

产物目录：${OUTPUT_DIR}
  ├─ ${MODEL_NAME}.mlmodelc                          ← Core ML 模型（编码器 + CTC 头）
  ├─ query_embeddings.f32                            ← 前缀 embedding 原始 float32（Swift 引擎读取）
  ├─ query_embeddings.npz                            ← 同上的 numpy 版（参考）
  ├─ am.mvn                                          ← CMVN 均值/方差（前处理）
  ├─ tokens.json                                     ← id → token 词表（后处理）
  ├─ chn_jpn_yue_eng_ko_spectok.bpe.model            ← SentencePiece BPE（参考）
  └─ config.yaml                                     ← 网络结构（参考）

模型 I/O 契约：
  输入  encoder_input : (1, 560, 1, T)  float16   （T ∈ {21,38,54,88,171,254,338,504}）
  输出  ctc_logits    : (1, 25055, 1, T) float16

✅  已接入 app：设置 → 语音输入 → 识别引擎选 SenseVoice → 「SenseVoice 模型目录」
    填上面这个 ${OUTPUT_DIR} 路径即可。（这不是 whisper 的 mlmodelc，走的是纯 Swift
    的独立 Core ML 推理链路，详见 SenseVoiceSmall/README.md。）

自检（可选，需 pip 环境仍在）：
  source ${VENV_DIR}/bin/activate
  cd ${REPO_DIR}
  python -m sensevoice_ane.inference some_16k.wav \\
      --model-dir "${MODEL_CACHE}" --mlpackage "${MLPACKAGE}"
EOF
