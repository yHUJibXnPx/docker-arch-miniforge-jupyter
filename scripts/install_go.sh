#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

log_info "Starting download and configuration of Go..."

# https://goproxy.cn,direct
#export GOPROXY='https://proxy.golang.org,direct'
# sum.golang.google.cn
#export GOSUMDB=off

# 获取数据
raw_data=$(curl -s "https://go.dev/dl/?mode=json&include=all")

# 跨平台提取所有版本号 (macOS 用 Perl, Linux 有 jq 用 jq)
if command -v jq >/dev/null 2>&1; then
  versions=$(echo "$raw_data" | jq -r '.[].version')
else
  versions=$(echo "$raw_data" | perl -nle 'print $1 while /"version":\s*"([^"]+)"/g')
fi

# 过滤出最新稳定版和测试版
stable=$(echo "$versions" | awk '!seen[$0]++' | grep -vE 'rc|beta' | head -n1)
pre=$(echo "$versions" | awk '!seen[$0]++' | grep -E 'rc|beta' | head -n1)

echo "--- 结果分析 ---"
echo "最新稳定: $stable"
echo "最新测试: ${pre:-无}"

# 提取主版本用于比对
# 使用更健壮的提取方式：go1.26.1 -> 1.26
s_num=$(echo "$stable" | perl -nle 'print $1 if /go(\d+\.\d+)/')
p_num=$(echo "$pre" | perl -nle 'print $1 if /go(\d+\.\d+)/')

# 最终决策
if [ -n "$p_num" ] && [ "$(echo "$p_num > $s_num" | bc -l 2>/dev/null || awk "BEGIN {if ($p_num > $s_num) print 1; else print 0}")" -eq 1 ]; then
  echo "结论：测试版 $pre 是更新的架构，建议尝鲜。"
  final="$pre"
else
  echo "结论：$stable 是当前最强版本。"
  final="$stable"
fi

echo "最终选择: $final"
GO_VERSION=$final

log_info "GO 最新版本: ${GO_VERSION}"

# 限定范围以后有其他的再加
case "${TARGETOS}" in
  linux)
    log_info "Supported TARGETOS: ${TARGETOS}"
    case "${TARGETARCH}" in
      arm64)
        log_info "Supported architecture: ${TARGETARCH}"
        ;;
      amd64)
        log_info "Supported architecture: ${TARGETARCH}"
        ;;
      *)
        log_error "Unsupported architecture: ${TARGETARCH}"
        exit 1
        ;;
    esac
    ;;
  # 这本身不用于docker只是用于记录这段代码可能永远不会生效
  darwin)
    log_info "Supported TARGETOS: ${TARGETOS}"
    case "${TARGETARCH}" in
      arm64)
        log_info "Supported architecture: ${TARGETARCH}"
        ;;
      amd64)
        log_info "Supported architecture: ${TARGETARCH}"
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

URI_DOWNLOAD=""
TARGET_FILE=""
log_info "Searching for a valid release across recent versions..."

TEMP_URL=https://go.dev/dl/${GO_VERSION}.${TARGETOS}-${TARGETARCH}.tar.gz

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
    log_success "Found valid binary: ${GO_VERSION}.${TARGETOS}-${TARGETARCH}.tar.gz in version ${GO_VERSION}"
    URI_DOWNLOAD="${TEMP_URL}"
    TARGET_FILE="${GO_VERSION}.${TARGETOS}-${TARGETARCH}.tar.gz"
fi

# 检查最终是否找到了文件
if [[ -z "${URI_DOWNLOAD}" ]]; then 
    log_error "Critical Error: Could not find any valid download for ${TARGETARCH} in the last 5 releases."
    exit 1 
fi

# 如果 find_and_download 失败，脚本会在这里退出 (因为 set -e)
log_info "Download URL: ${URI_DOWNLOAD}"

# 检查文件是否存在
if [[ -f "/tmp/${TARGET_FILE}" ]]; then
  log_info "File already exists: /tmp/${TARGET_FILE}"
  rm -fv "/tmp/${TARGET_FILE}"
fi

# 如果文件不存在
if [[ ! -f "/tmp/${TARGET_FILE}" ]]; then
  log_info "Downloading file..."
  # 临时取消 set -e（如果你之前开启了严格模式）防止炸脚本
  set +e
  curl -L -C - --retry 3 --retry-delay 5 --progress-bar -o "/tmp/${TARGET_FILE}" "${URI_DOWNLOAD}"
  set -e
  log_info "File download successfully."
fi

tar xvf "/tmp/${TARGET_FILE}" -C /opt/

# 更精准地定位刚刚解压出来的目录
NEWGO=/opt/go

# 将激活环境写入配置文件中，保留长期有效
# 在 docker 非交互式容器中毫无意义，可以没有，但是我希望，这能帮助我理解
cat << '469138946ba5fa' | tee -a /etc/environment "${HOME}/.profile"
# GOROOT: 指向 Go 的安装目录（即解压的位置）
export GOROOT=/opt/go
# GOPATH: 你的工作区（存放下载的第三方包和编译后的二进制工具）
# 建议放在家目录下，避免 /opt 目录的权限问题
export GOPATH=$HOME/go
# PATH: 将 Go 编译器和 GoNB 等工具加入系统搜索路径
# 必须包含 GOROOT/bin（go命令）和 GOPATH/bin（安装的插件）
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin
469138946ba5fa

# 获取当前 shell 名称
CURRENT_SHELL=$(basename "${SHELL}")

log_info "Detected shell: ${CURRENT_SHELL}"

case "${CURRENT_SHELL}" in
  bash)
    if ! grep -qEi 'GOROOT|GOPATH' "${HOME}/.bashrc"; then
      log_info "Initializing go for bash..."
      # 固化 go 环境
      # 在 docker 非交互式容器中毫无意义，可以没有，但是我希望，这能帮助我理解
      cat << '469138946ba5fa' | tee -a /etc/skel/.bashrc "${HOME}/.bashrc"
# GOROOT: 指向 Go 的安装目录（即解压的位置）
export GOROOT=/opt/go
# GOPATH: 你的工作区（存放下载的第三方包和编译后的二进制工具）
# 建议放在家目录下，避免 /opt 目录的权限问题
export GOPATH=$HOME/go
# PATH: 将 Go 编译器和 GoNB 等工具加入系统搜索路径
# 必须包含 GOROOT/bin（go命令）和 GOPATH/bin（安装的插件）
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin
469138946ba5fa
    fi
    ;;
  zsh)
    if ! grep -qEi 'GOROOT|GOPATH' "${HOME}/.zshrc"; then
      log_info "Initializing go for zsh..."
      # 固化 go 环境
      # 在 docker 非交互式容器中毫无意义，可以没有，但是我希望，这能帮助我理解
      cat << '469138946ba5fa' | tee -a /etc/skel/.zshrc "${HOME}/.zshrc"
# GOROOT: 指向 Go 的安装目录（即解压的位置）
export GOROOT=/opt/go
# GOPATH: 你的工作区（存放下载的第三方包和编译后的二进制工具）
# 建议放在家目录下，避免 /opt 目录的权限问题
export GOPATH=$HOME/go
# PATH: 将 Go 编译器和 GoNB 等工具加入系统搜索路径
# 必须包含 GOROOT/bin（go命令）和 GOPATH/bin（安装的插件）
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin
469138946ba5fa
    fi
    ;;
  *)
    log_error "Unsupported shell: ${CURRENT_SHELL}"
    exit 1
    ;;
esac

log_info "GO configuration completed."
