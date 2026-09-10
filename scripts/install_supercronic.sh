#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"
log_info "Starting download and configuration of SuperCronic..."

# GitHub 项目 URI
URI="aptible/supercronic"

# 限定范围以后有其他的再加
case "${TARGETOS}" in
  linux)
    log_info "Supported TARGETOS: ${TARGETOS}"
    case "${TARGETARCH}" in
      arm64)
        log_info "Supported TARGETARCH: ${TARGETARCH}"
        ;;
      amd64)
        log_info "Supported TARGETARCH: ${TARGETARCH}"
        ;;
      *)
        log_error "Unsupported architecture: ${TARGETOS}-${TARGETARCH}"
        exit 1
        ;;
    esac
    ;;
  # 这本身不用于docker只是用于记录这段代码可能永远不会生效
  darwin)
    TARGETOS="mac"
    log_info "Supported TARGETOS: ${TARGETOS}"
    case "${TARGETARCH}" in
      arm64)
        log_info "Supported TARGETARCH: ${TARGETARCH}"
        ;;
      amd64)
        log_info "Supported TARGETARCH: ${TARGETARCH}"
        ;;
      *)
        log_error "Unsupported architecture: ${TARGETOS}-${TARGETARCH}"
        exit 1
        ;;
    esac
    ;;
  *)
    log_error "Unsupported TARGETOS: ${TARGETOS}"
    exit 1
    ;;
esac

# 输出最终平台和架构
log_info "TARGETOS-TARGETARCH: ${TARGETOS}-${TARGETARCH}"

# 获取最近的 5 个版本标签 (以前只取了 head -n 1)
TAG_LIST=$(curl -sL "https://github.com/${URI}/releases" | grep -Eo '/releases/tag/[^"]+' | awk -F'/tag/' '{print $2}' | head -n 5)

URI_DOWNLOAD=""
TARGET_FILE=""
CURRENT_VERSION=""
TAG=""
log_info "Searching for a valid release across recent versions..."

# 外层循环：遍历版本标签
for CURRENT_TAG in $TAG_LIST; do
  # 处理版本字符串逻辑
  # 例如：supercronic v0.2.41 -> v0.2.40
  log_info "Checking version: ${CURRENT_TAG}"
  
  BASE_URL="https://github.com/${URI}/releases/download/${CURRENT_TAG}"
  
  # 定义可能的命名格式
  FILE_PATTERNS=(
    # 模板 A: 完整版本号命名（例如：supercronic-linux-amd64）
    "supercronic-${TARGETOS}-${TARGETARCH}"
  )

  # 内层循环：在当前版本下测试不同的文件名
  MATCH_FOUND=false
  for FILE_PATTERN in "${FILE_PATTERNS[@]}"; do
    TEMP_URL="${BASE_URL}/${FILE_PATTERN}"
    
    # 使用 curl --head (或 -I) 只获取头部信息，并检查 HTTP 状态码
    # -s 保持静默模式，-L 遵循重定向，-I/--head 只获取头部
    # 检查 HTTP 状态码是否为 200 (OK) 或 3xx (重定向)
    # 临时取消 set -e（如果你之前开启了严格模式）防止炸脚本
    set +e
    # 使用 -o /dev/null 屏蔽输出，用 -w 获取状态码
    HTTP_STATUS=$(curl -sL --retry 3 --retry-delay 5 -I -o /dev/null -w "%{http_code}" "${TEMP_URL}")
    set -e
    # 只要状态码是 200 (成功) 或 302 (重定向到 CDN)
    if [[ "$HTTP_STATUS" -eq 200 || "$HTTP_STATUS" -eq 302 ]]; then
      log_success "Found valid binary: ${FILE_PATTERN} in version ${CURRENT_TAG}"
      TAG="${CURRENT_TAG}"
      URI_DOWNLOAD="${TEMP_URL}"
      TARGET_FILE="${FILE_PATTERN}"
      MATCH_FOUND=true
      break # 跳出内层循环
    fi
  done

  if [ "$MATCH_FOUND" = true ]; then
    break # 找到可用的了，跳出外层版本循环
  fi
  
  log_warning "No ${TARGETOS}-${TARGETARCH} binaries found for ${CURRENT_TAG}, trying previous release..."
done

# 检查最终是否找到了文件
if [[ -z "${URI_DOWNLOAD}" || -z "${TAG}" ]]; then 
  log_error "Critical Error: Could not find any valid download for ${TARGETOS}-${TARGETARCH} in the last 5 releases."
  exit 1
fi

# 如果 find_and_download 失败，脚本会在这里退出 (因为 set -e)
# 如果成功，则继续定义链接
SUPERCRONIC_SHA1SUM=$(
  curl -fsSL "https://github.com/${URI}/releases/tag/${TAG}" \
  | grep -A1 "${TARGET_FILE}" \
  | sed -n 's/.*SUPERCRONIC_SHA1SUM=\([a-f0-9]\{40\}\).*/\1/p' \
  | awk '!seen[$0]++' \
  | head -n1
)

if [[ -z "${SUPERCRONIC_SHA1SUM}" ]]; then
  log_error "Failed to resolve SHA1 checksum for ${TARGET_FILE} (${TAG})"
  exit 1
fi

log_info "Download URL: ${URI_DOWNLOAD}"
log_info "SHA1 SUM: ${SUPERCRONIC_SHA1SUM}"

# 检查文件是否存在
if [[ -f "/usr/local/bin/${TARGET_FILE}" ]]; then
  log_info "File already exists: /usr/local/bin/${TARGET_FILE}"

  # 校验文件完整性
  # sha1sum 校验依赖 perl 可能 linux 系统需要手动安装
  log_info "Verifying file integrity for /usr/local/bin/${TARGET_FILE}..."

  pushd /usr/local/bin/
  if ! echo "${SUPERCRONIC_SHA1SUM} ${TARGET_FILE}" | sha1sum -c -; then
    log_warning "SHA1 checksum failed. Removing file and retrying..."
    rm -fv "/usr/local/bin/${TARGET_FILE}"
  else
    log_info "File integrity verified successfully."
  fi
  popd
fi

# 如果文件不存在或之前校验失败
if [[ ! -f "/usr/local/bin/${TARGET_FILE}" ]]; then
  log_info "Downloading file..."
  # 临时取消 set -e（如果你之前开启了严格模式）防止炸脚本
  set +e
  curl -L -C - --retry 3 --retry-delay 5 --progress-bar -o "/usr/local/bin/${TARGET_FILE}" "${URI_DOWNLOAD}"
  set -e

  # 校验完整性
  # shasum 校验依赖 perl 可能 linux 系统需要手动安装
  log_info "Verifying file integrity for /usr/local/bin/${TARGET_FILE}..."

  pushd /usr/local/bin/
  if ! echo "${SUPERCRONIC_SHA1SUM} ${TARGET_FILE}" | sha1sum -c -; then
    log_error "Download failed: SHA1 checksum does not match."
    exit 1
  else
    log_info "File integrity verified successfully."
  fi
  popd
fi

chmod -v +x "/usr/local/bin/${TARGET_FILE}"
ln -fsv "/usr/local/bin/${TARGET_FILE}" /usr/local/bin/supercronic

log_info "SuperCronic configuration completed."