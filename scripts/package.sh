#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# cleaner macOS 多架构自动化编译与打包脚本
# 用法:
#   ./scripts/package.sh [arm64|x86_64|universal|all]
# 默认: all (同时产出 arm64、x86_64、universal 三套 .dmg 与 .zip 安装包)
# ==============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TARGET_MODE="${1:-all}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/DerivedData}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
ENTITLEMENTS_MAIN="$ROOT_DIR/Lemon/Tencent Lemon.entitlements"
ENTITLEMENTS_MONITOR="$ROOT_DIR/Tools/LemonMonitor/LemonMonitor/LemonMonitor.entitlements"

mkdir -p "$DIST_DIR"

log() {
  printf "\033[1;36m[cleaner-packager]\033[0m %s\n" "$*"
}

# 对 .app 进行由内向外的 Ad-hoc 签名（Apple Silicon 必须具备有效签名方可启动进程）
sign_app_bundle() {
  local app_bundle="$1"
  log "Signing bundle (inside-out): $app_bundle"

  # 1. 签名内部嵌套应用 LemonMonitor.app 及其 Frameworks
  local monitor_app="$app_bundle/Contents/Library/LoginItems/LemonMonitor.app"
  if [ -d "$monitor_app" ]; then
    if [ -d "$monitor_app/Contents/Frameworks" ]; then
      find "$monitor_app/Contents/Frameworks" -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) -print0 | while IFS= read -r -d '' item; do
        codesign --force --sign - --timestamp=none "$item"
      done
    fi
    if [ -f "$ENTITLEMENTS_MONITOR" ]; then
      codesign --force --sign - --timestamp=none --entitlements "$ENTITLEMENTS_MONITOR" "$monitor_app"
    else
      codesign --force --sign - --timestamp=none "$monitor_app"
    fi
  fi

  # 2. 签名主应用 Frameworks 目录内所有子项（含 .framework、LemonDaemon 及嵌入的 Launchd plist）
  if [ -d "$app_bundle/Contents/Frameworks" ]; then
    find "$app_bundle/Contents/Frameworks" -maxdepth 1 -mindepth 1 -print0 | while IFS= read -r -d '' item; do
      codesign --force --sign - --timestamp=none "$item"
    done
  fi

  # 3. 签名主应用 cleaner.app
  if [ -f "$ENTITLEMENTS_MAIN" ]; then
    codesign --force --deep --sign - --timestamp=none --entitlements "$ENTITLEMENTS_MAIN" "$app_bundle"
  else
    codesign --force --deep --sign - --timestamp=none "$app_bundle"
  fi

  codesign --verify --deep --strict "$app_bundle"
}

# 将指定架构的 cleaner.app 封装为 .dmg (带 Applications 拖拽快捷方式) 和 .zip
create_archives() {
  local app_bundle="$1"
  local arch_label="$2"
  local dmg_name="cleaner-macos-${arch_label}.dmg"
  local zip_name="cleaner-macos-${arch_label}.zip"
  local dmg_path="$DIST_DIR/$dmg_name"
  local zip_path="$DIST_DIR/$zip_name"

  log "Verifying binary architectures for [$arch_label]..."
  lipo -info \
    "$app_bundle/Contents/MacOS/cleaner" \
    "$app_bundle/Contents/Frameworks/LemonDaemon" \
    "$app_bundle/Contents/Library/LoginItems/LemonMonitor.app/Contents/MacOS/LemonMonitor"

  sign_app_bundle "$app_bundle"

  # 打包 .zip (保留 macOS 资源派生与符号链接)
  log "Creating ZIP archive: $zip_path"
  rm -f "$zip_path"
  ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$zip_path"

  # 打包 .dmg (带 /Applications 软链接，支持拖拽安装)
  log "Creating DMG installer: $dmg_path"
  rm -f "$dmg_path"
  local staging_dir
  staging_dir="$(mktemp -d)"
  ditto "$app_bundle" "$staging_dir/cleaner.app"
  ln -s /Applications "$staging_dir/Applications"

  hdiutil create \
    -volname "cleaner" \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDZO \
    "$dmg_path" >/dev/null

  rm -rf "$staging_dir"

  # 生成 SHA256 校验值
  (
    cd "$DIST_DIR"
    shasum -a 256 "$dmg_name" "$zip_name" >> "$DIST_DIR/SHA256SUMS.txt"
  )
  log "Finished packaging [$arch_label]: $dmg_path & $zip_path"
}

build_xcode() {
  local archs_arg="$1"
  if [ "${SKIP_XCODEBUILD:-0}" = "1" ] && [ -d "$DERIVED_DATA_PATH/Build/Products/Release/cleaner.app" ]; then
    log "Skipping xcodebuild (reusing $DERIVED_DATA_PATH/Build/Products/Release/cleaner.app)..."
    return 0
  fi
  log "Building cleaner.app with ARCHS='$archs_arg'..."
  xcodebuild \
    -workspace "$ROOT_DIR/Lemon.xcworkspace" \
    -scheme Lemon \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    ARCHS="$archs_arg" \
    ONLY_ACTIVE_ARCH=NO \
    MACOSX_DEPLOYMENT_TARGET=12.0 \
    ENABLE_USER_SCRIPT_SANDBOXING=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build
}

rm -f "$DIST_DIR/SHA256SUMS.txt"

case "$TARGET_MODE" in
  arm64)
    build_xcode "arm64"
    BUILT_APP="$DERIVED_DATA_PATH/Build/Products/Release/cleaner.app"
    WORK_DIR="$(mktemp -d)"
    ditto --arch arm64 "$BUILT_APP" "$WORK_DIR/cleaner.app"
    create_archives "$WORK_DIR/cleaner.app" "arm64"
    rm -rf "$WORK_DIR"
    ;;
  x86_64)
    build_xcode "x86_64"
    BUILT_APP="$DERIVED_DATA_PATH/Build/Products/Release/cleaner.app"
    WORK_DIR="$(mktemp -d)"
    ditto --arch x86_64 "$BUILT_APP" "$WORK_DIR/cleaner.app"
    create_archives "$WORK_DIR/cleaner.app" "x86_64"
    rm -rf "$WORK_DIR"
    ;;
  universal)
    build_xcode "arm64 x86_64"
    BUILT_APP="$DERIVED_DATA_PATH/Build/Products/Release/cleaner.app"
    WORK_DIR="$(mktemp -d)"
    ditto "$BUILT_APP" "$WORK_DIR/cleaner.app"
    create_archives "$WORK_DIR/cleaner.app" "universal"
    rm -rf "$WORK_DIR"
    ;;
  all)
    build_xcode "arm64 x86_64"
    BUILT_APP="$DERIVED_DATA_PATH/Build/Products/Release/cleaner.app"
    WORK_DIR="$(mktemp -d)"

    # 1. Universal (arm64 + x86_64 双架构通用包)
    mkdir -p "$WORK_DIR/universal"
    ditto "$BUILT_APP" "$WORK_DIR/universal/cleaner.app"
    create_archives "$WORK_DIR/universal/cleaner.app" "universal"

    # 2. Apple Silicon (M1/M2/M3/M4 纯 arm64 包)
    mkdir -p "$WORK_DIR/arm64"
    ditto --arch arm64 "$BUILT_APP" "$WORK_DIR/arm64/cleaner.app"
    create_archives "$WORK_DIR/arm64/cleaner.app" "arm64"

    # 3. Intel (纯 x86_64 包)
    mkdir -p "$WORK_DIR/x86_64"
    ditto --arch x86_64 "$BUILT_APP" "$WORK_DIR/x86_64/cleaner.app"
    create_archives "$WORK_DIR/x86_64/cleaner.app" "x86_64"

    rm -rf "$WORK_DIR"
    ;;
  *)
    echo "Usage: $0 [arm64|x86_64|universal|all]" >&2
    exit 1
    ;;
esac

log "All artifacts generated in: $DIST_DIR"
ls -lh "$DIST_DIR"
