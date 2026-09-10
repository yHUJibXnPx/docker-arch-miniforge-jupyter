#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

log_info "Starting download and configuration of OpenJDK..."

# 获取数据
raw_data=$(curl -s "https://api.adoptium.net/v3/info/available_releases")

# 增强型提取函数 (兼容 macOS Perl)
# 它可以提取数字，如果没有找到对应的键，则返回空
extract_val() {
  # 匹配 "key": 27 或 "key":27
  echo "$raw_data" | perl -nle "print \$1 if /\"$1\":\s*(\d+)/" | head -n1
}

lts_ver=$(extract_val "most_recent_lts")
stable_ver=$(extract_val "most_recent_feature_release")
# 这里的 tip_version 就是你看到的 27
future_ver=$(extract_val "tip_version")

echo "--- OpenJDK 深度探测 ---"
echo "长期支持版本 (LTS): Java $lts_ver"
echo "当前正式发布 (GA): Java $stable_ver"
echo "源码演进版本 (Tip): Java $future_ver"

# 智能决策
echo "---"
if [ "$future_ver" -gt "$stable_ver" ]; then
  echo "提示：Java $future_ver 已经在路上（Tip），但目前稳妥的最新版是 $stable_ver。"
  newest_logic=$future_ver
else
  newest_logic=$stable_ver
fi

echo "====================="
echo "最高版本号，它是: Java $newest_logic"
JDK_VERSION=$newest_logic

# GitHub 项目 URI
URI="adoptium/temurin${JDK_VERSION}-binaries"

# 限定范围以后有其他的再加
case "${TARGETOS}" in
  linux)
    log_info "Supported TARGETOS: ${TARGETOS}"
    case "${TARGETARCH}" in
      arm64)
        TARGETARCH="aarch64"
        ;;
      amd64)
        TARGETARCH="x64"
        ;;
      *)
        log_error "Unsupported architecture: ${TARGETARCH}"
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
        TARGETARCH="aarch64"
        ;;
      amd64)
        TARGETARCH="x64"
        ;;
      *)
        log_error "Unsupported architecture: ${TARGETARCH}"
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
log_info "TARGETOS: ${TARGETOS}"
log_info "TARGETARCH: ${TARGETARCH}"

# 获取最近的 5 个版本标签 (以前只取了 head -n 1)
TAG_LIST=$(curl -sL "https://github.com/${URI}/releases" | grep -Eo '/releases/tag/[^"]+' | awk -F'/tag/' '{print $2}' | head -n 5)

URI_DOWNLOAD=""
TARGET_FILE=""
SHA256_FILE=""
CURRENT_VERSION=""
log_info "Searching for a valid release across recent versions..."

# 外层循环：遍历版本标签
for CURRENT_TAG in $TAG_LIST; do
    # 处理版本字符串逻辑
    # 例如：jdk-21.0.1+12 -> 21.0.1_12
    CURRENT_VERSION=$(echo "${CURRENT_TAG#jdk-}" | sed 's;%2B;_;g;s;-beta;;g')
    
    log_info "Checking version: ${CURRENT_TAG} (Internal ID: ${CURRENT_VERSION})"
    
    BASE_URL="https://github.com/${URI}/releases/download/${CURRENT_TAG}"
    
    # 定义可能的命名格式
    FILE_PATTERNS=(
        # 模板 A: beta 完整版本号命名（例如：OpenJDK26U-jdk_x64_linux_hotspot_26_27-ea.tar.gz）
        "OpenJDK${JDK_VERSION}U-jdk_${TARGETARCH}_${TARGETOS}_hotspot_${CURRENT_VERSION}.tar.gz"
        # 模板 B: beta/stable 无版本号命名（例如：OpenJDK-jdk_x64_linux_hotspot_26_26-ea.tar.gz）
        "OpenJDK-jdk_${TARGETARCH}_${TARGETOS}_hotspot_${CURRENT_VERSION}.tar.gz"
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
            URI_DOWNLOAD="${TEMP_URL}"
            TARGET_FILE="${FILE_PATTERN}"
            SHA256_FILE="${FILE_PATTERN}.sha256.txt"
            MATCH_FOUND=true
            break # 跳出内层循环
        fi
    done

    if [ "$MATCH_FOUND" = true ]; then
        break # 找到可用的了，跳出外层版本循环
    fi
    
    log_warning "No ${TARGETARCH} binaries found for ${CURRENT_TAG}, trying previous release..."
done

# 检查最终是否找到了文件
if [[ -z "${URI_DOWNLOAD}" ]]; then 
    log_error "Critical Error: Could not find any valid download for ${TARGETARCH} in the last 5 releases."
    exit 1 
fi

# 如果 find_and_download 失败，脚本会在这里退出 (因为 set -e)
# 如果成功，则继续定义链接
URI_SHA256="${URI_DOWNLOAD}.sha256.txt"
log_info "Download URL: ${URI_DOWNLOAD}"
log_info "SHA256 URL: ${URI_SHA256}"

# 检查文件是否存在
if [[ -f "/tmp/${TARGET_FILE}" ]]; then
  log_info "File already exists: /tmp/${TARGET_FILE}"
  
  # 删除旧的 SHA256 文件（如果存在）
  if [[ -f "/tmp/${SHA256_FILE}" ]]; then
    log_info "Removing old SHA256 file: /tmp/${SHA256_FILE}"
    rm -fv "/tmp/${SHA256_FILE}"
  fi

  # 下载新的 SHA256 文件
  log_info "Downloading SHA256 file..."
  # 临时取消 set -e（如果你之前开启了严格模式）防止炸脚本
  set +e
  curl -L -C - --retry 3 --retry-delay 5 --progress-bar -o "/tmp/${SHA256_FILE}" "${URI_SHA256}"
  set -e

  # 校验文件完整性
  # shasum 校验依赖 perl 可能 linux 系统需要手动安装
  log_info "Verifying file integrity for /tmp/${TARGET_FILE}..."
  cd /tmp
  if ! shasum -a 256 -c "${SHA256_FILE}"; then
    log_warning "SHA256 checksum failed. Removing file and retrying..."
    rm -fv "/tmp/${TARGET_FILE}"
  else
    log_info "File integrity verified successfully."
  fi
fi

# 如果文件不存在或之前校验失败
if [[ ! -f "/tmp/${TARGET_FILE}" ]]; then
  log_info "Downloading file..."
  # 临时取消 set -e（如果你之前开启了严格模式）防止炸脚本
  set +e
  curl -L -C - --retry 3 --retry-delay 5 --progress-bar -o "/tmp/${TARGET_FILE}" "${URI_DOWNLOAD}"
  set -e

  # 删除旧的 SHA256 文件并重新下载
  if [[ -f "/tmp/${SHA256_FILE}" ]]; then
    log_info "Removing old SHA256 file: /tmp/${SHA256_FILE}"
    rm -fv "/tmp/${SHA256_FILE}"
  fi
  log_info "Downloading SHA256 file..."
  # 临时取消 set -e（如果你之前开启了严格模式）防止炸脚本
  set +e
  curl -L -C - --retry 3 --retry-delay 5 --progress-bar -o "/tmp/${SHA256_FILE}" "${URI_SHA256}"
  set -e

  # 校验完整性
  # shasum 校验依赖 perl 可能 linux 系统需要手动安装
  log_info "Verifying file integrity for /tmp/${TARGET_FILE}..."
  cd /tmp
  if ! shasum -a 256 -c "${SHA256_FILE}"; then
    log_error "Download failed: SHA256 checksum does not match."
    exit 1
  else
    log_info "File integrity verified successfully."
  fi
fi

tar xvf "/tmp/${TARGET_FILE}" -C /opt/

#NEWJDK=$(ls -1d /opt/jdk* | sort | tail -n 1)
# 更精准地定位刚刚解压出来的目录
# Temurin 解压后的文件夹通常包含版本号，我们可以通过这种方式找：
NEWJDK=$(ls -1d /opt/jdk-${CURRENT_VERSION%_*}* 2>/dev/null | head -n 1 || ls -1d /opt/jdk* | sort -V | tail -n 1)
mkdir -p ${HOME}/.jbang && chmod -v 755 ${HOME}/.jbang
ln -fs "${NEWJDK}" "${HOME}/.jbang/currentjdk"

# 将激活环境写入配置文件中，保留长期有效
# 在 docker 非交互式容器中毫无意义，可以没有，但是我希望，这能帮助我理解
cat << '469138946ba5fa' | tee -a /etc/environment "${HOME}/.profile"
export JAVA_HOME=${HOME}/.jbang/currentjdk
export CLASSPATH=.:${JAVA_HOME}/lib
export PATH=${PATH}:${JAVA_HOME}/bin
469138946ba5fa

# 获取当前 shell 名称
CURRENT_SHELL=$(basename "${SHELL}")

log_info "Detected shell: ${CURRENT_SHELL}"

case "${CURRENT_SHELL}" in
  bash)
    if ! grep -qEi 'JAVA_HOME|CLASSPATH' "${HOME}/.bashrc"; then
      log_info "Initializing jdk for bash..."
      # 固化 jdk 环境
      # 在 docker 非交互式容器中毫无意义，可以没有，但是我希望，这能帮助我理解
      cat << '469138946ba5fa' | tee -a /etc/skel/.bashrc "${HOME}/.bashrc"
export JAVA_HOME=${HOME}/.jbang/currentjdk
export CLASSPATH=.:${JAVA_HOME}/lib
export PATH=${PATH}:${JAVA_HOME}/bin
469138946ba5fa
    fi
    ;;
  zsh)
    if ! grep -qEi 'JAVA_HOME|CLASSPATH' "${HOME}/.zshrc"; then
      log_info "Initializing jdk for zsh..."
      # 固化 jdk 环境
      # 在 docker 非交互式容器中毫无意义，可以没有，但是我希望，这能帮助我理解
      cat << '469138946ba5fa' | tee -a /etc/skel/.zshrc "${HOME}/.zshrc"
export JAVA_HOME=${HOME}/.jbang/currentjdk
export CLASSPATH=.:${JAVA_HOME}/lib
export PATH=${PATH}:${JAVA_HOME}/bin
469138946ba5fa
    fi
    ;;
  *)
    log_error "Unsupported shell: ${CURRENT_SHELL}"
    exit 1
    ;;
esac

log_info "OpenJDK configuration completed."
