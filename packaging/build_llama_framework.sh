#!/bin/bash
#
# 构建 Frameworks/llama.framework —— 把 llama.cpp 的静态库合并成单个自包含的
# 动态库，封装为 macOS framework，供 Prompt 输入法进程内加载 GGUF 推理使用。
#
# 为什么是动态 framework 而不是直接静态链接 .a：
#   whisper.framework 已经内嵌了一份 ggml（导出 1000+ 个 ggml_* 符号）。若把
#   llama.cpp 的 ggml 静态库 force_load 进主可执行文件，会与 whisper 的 ggml
#   产生符号重复（且两者版本可能不一致）。做成独立动态 framework 后，macOS
#   two-level namespace 让两份 ggml 各自隔离，互不干扰 —— 与 whisper.framework
#   的集成方式完全一致。
#
# 前置条件：
#   已在 ../ChineseErrorCorrector/llama.cpp/build 下用
#     -DBUILD_SHARED_LIBS=OFF -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_BLAS=ON
#   编译出静态库（prepare.sh 会完成）。Metal 着色器已内嵌进 .a，运行期无需 .metallib。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LLAMA_DIR="${LLAMA_CPP_DIR:-${PROMPT_ROOT}/../ChineseErrorCorrector/llama.cpp}"
BUILD="${LLAMA_DIR}/build"
INC="${LLAMA_DIR}/include"
GGML_INC="${LLAMA_DIR}/ggml/include"

FW="${PROMPT_ROOT}/Frameworks/llama.framework"
VER="${FW}/Versions/A"

for a in \
    "${BUILD}/src/libllama.a" \
    "${BUILD}/ggml/src/libggml.a" \
    "${BUILD}/ggml/src/libggml-base.a" \
    "${BUILD}/ggml/src/libggml-cpu.a" \
    "${BUILD}/ggml/src/ggml-metal/libggml-metal.a" \
    "${BUILD}/ggml/src/ggml-blas/libggml-blas.a"
do
    [ -f "$a" ] || { echo "缺少静态库: $a" >&2; echo "请先在 llama.cpp 下运行 prepare.sh 编译" >&2; exit 1; }
done

echo "清理旧 framework..."
rm -rf "${FW}"
mkdir -p "${VER}/Headers" "${VER}/Modules" "${VER}/Resources"

echo "合并静态库为动态库 (arch arm64)..."
# -all_load: 整库加载，确保 Metal/CPU/BLAS 后端的全局构造函数被保留，从而注册进
#            ggml backend registry（否则静态链接里未被引用的目标文件会被裁剪掉）。
clang++ -dynamiclib -arch arm64 \
    -mmacosx-version-min=13.3 \
    -install_name @rpath/llama.framework/Versions/Current/llama \
    -Wl,-all_load \
    "${BUILD}/src/libllama.a" \
    "${BUILD}/ggml/src/libggml.a" \
    "${BUILD}/ggml/src/libggml-base.a" \
    "${BUILD}/ggml/src/libggml-cpu.a" \
    "${BUILD}/ggml/src/ggml-metal/libggml-metal.a" \
    "${BUILD}/ggml/src/ggml-blas/libggml-blas.a" \
    -framework Metal -framework MetalKit -framework Foundation -framework Accelerate \
    -lc++ \
    -o "${VER}/llama"

echo "拷贝头文件..."
cp "${INC}/llama.h" "${VER}/Headers/"
cp "${INC}/llama-cpp.h" "${VER}/Headers/" 2>/dev/null || true
# llama.h #include 的 ggml 头文件（需与 llama.h 同目录可见）
for h in ggml.h ggml-cpu.h ggml-backend.h ggml-alloc.h ggml-opt.h gguf.h; do
    cp "${GGML_INC}/${h}" "${VER}/Headers/"
done

echo "写入 module.modulemap..."
cat > "${VER}/Modules/module.modulemap" <<'EOF'
framework module llama {
    header "llama.h"

    link "c++"
    link framework "Accelerate"
    link framework "Metal"
    link framework "MetalKit"
    link framework "Foundation"

    export *
}
EOF

echo "写入 Info.plist..."
cat > "${VER}/Resources/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>    <string>en</string>
    <key>CFBundleExecutable</key>           <string>llama</string>
    <key>CFBundleIdentifier</key>           <string>org.ggml.llama</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key>                 <string>llama</string>
    <key>CFBundlePackageType</key>          <string>FMWK</string>
    <key>CFBundleShortVersionString</key>   <string>1.0</string>
    <key>CFBundleVersion</key>              <string>1</string>
    <key>MinimumOSVersion</key>             <string>13.3</string>
    <key>CFBundleSupportedPlatforms</key>
    <array><string>MacOSX</string></array>
    <key>DTPlatformName</key>   <string>macosx</string>
    <key>DTSDKName</key>        <string>macosx13.3</string>
</dict>
</plist>
EOF

echo "创建 framework 符号链接..."
ln -sfn A "${FW}/Versions/Current"
ln -sfn Versions/Current/llama   "${FW}/llama"
ln -sfn Versions/Current/Headers "${FW}/Headers"
ln -sfn Versions/Current/Modules "${FW}/Modules"
ln -sfn Versions/Current/Resources "${FW}/Resources"

echo ""
echo "完成: ${FW}"
otool -D "${VER}/llama"
echo "大小: $(du -h "${VER}/llama" | cut -f1)"
