#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

log_info "Starting system initialization..."

# 设置 DEBIAN_FRONTEND 为 noninteractive，这样 tzdata 就不会进入交互模式
# export DEBIAN_FRONTEND=noninteractive
# 设置时区
# TZ='Asia/Shanghai'

# 优化：为 apt update 增加重试逻辑 (核心！)
retry_apt_update() {
  local retries=5
  local sleep_seconds=5
  for ((i=1; i<=retries; i++)); do
    log_info "Apt update (attempt ${i}/${retries})"
    if apt-get update --allow-releaseinfo-change; then return 0; fi
    log_warning "Apt update failed, cleaning lists and retrying..."
    rm -rf /var/lib/apt/lists/*
    sleep $sleep_seconds
    sleep_seconds=$((sleep_seconds * 2))
  done
  log_error "Apt update failed after ${retries} attempts."
  exit 1
}

# linux 包 apt 安装带重试逻辑
# Filter to get only missing packages
# get_missing_packages 改回返回数组（最安全）
get_missing_packages() {
  local missing=()
  for pkg in "$@"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
      missing+=("$pkg")
    fi
  done
  # 用空格连接数组元素，无前导/尾随空格
  echo "${missing[*]}"   # [*] 用空格连接
}

# Bulk install with retries, using eatmydata if available
# retry_apt_install_bulk 函数（改的这个版本其实不错，保留）
retry_apt_install_bulk() {
  local retries=3
  local sleep_seconds=2
  local pkgs=("$@")
  if [ ${#pkgs[@]} -eq 0 ]; then
    log_info "No packages to install, skipping."
    return 0
  fi

  local base_cmd="apt-get"
  local base_args=(-y install --no-install-recommends)

  # 由于最近总是发现构建时安装软件少包也不报错退出，所以注释换成 eatmydata apt-get 安装方式
  #if command -v eatmydata >/dev/null 2>&1 && command -v aptitude >/dev/null 2>&1; then
    #base_cmd="eatmydata"
    #base_args=(aptitude --without-recommends -o APT::Get::Fix-Missing=true -y install)
  #fi

  log_info "Installing ${#pkgs[@]} packages with: $base_cmd ${base_args[*]}"
  log_info "Packages: ${pkgs[*]}"

  for ((i=1; i<=retries; i++)); do
    log_info "Attempt ${i}/${retries}"
    if "$base_cmd" "${base_args[@]}" "${pkgs[@]}"; then
      log_info "Installation successful."
      return 0
    else
      log_warning "Attempt ${i} failed, retrying..."
      sleep $sleep_seconds
      sleep_seconds=$((sleep_seconds * 2))
    fi
  done
  log_error "Failed after ${retries} attempts."
  exit 1
}

# 额外的APT工具和性能优化工具列表
# Core APT tools (small, install first)
core_apt_packages=(
  apt-transport-https  # 允许 APT 使用 HTTPS 协议访问软件仓库，提高传输安全性
  ca-certificates      # 根证书包，用于验证 SSL/TLS 链接，确保 HTTPS 通信安全
  aptitude             # APT 的文本界面前端工具，功能比 apt-get 更强大，也便于交互式使用（部分环境下可替代 apt-get）
  eatmydata            # 通过禁用 fsync 操作来加速软件安装过程，适用于临时构建环境以提高性能
)

# 所需系统软件包列表（基础系统工具和常用工具）
# System packages (split: essentials, then dev libs, then large fonts)
essential_packages=(
  clang              # 是 LLVM 官方的 C/C++ 编译器，和 GCC 类似，将 cmake 和 ninja 产生的编译指令最终都会调用它来：把 .cpp 变成 .o 再链接为 .so 或可执行程序
  gcc                # GCC（GNU编译器套件）是一个自由软件编译器集合
  tini               # 一个极简的 init 程序，用于容器中正确管理僵尸进程和信号转发
  git                # 分布式版本控制系统，用于代码管理和拉取远程仓库
  curl               # 命令行 HTTP 请求工具，用于获取 URL 内容和进行网络调试
  jq                 # 读取和写入json格式文件工具，用于处理 .json 格式的文件
  build-essential    # 一组构建工具（如 gcc、make 等），用于编译编译 C/C++ 等语言的代码
  bzip2              # 压缩和解压缩工具，用于处理 .bz2 格式的文件
  ffmpeg             # 用于处理音频、视频以及其他多媒体文件和流。
  #systemd           # 系统和服务管理器，有时用于基于 systemd 的容器或系统服务管理（在容器中用得较少，但有些基础镜像仍包含，配合cron会直接炸机）
  #logrotate          # Linux 下管理日志的标准工具
  inotify-tools      # 属于 inotify-tools 这个包，检查文件变化
  tzdata             # 时区数据包，确保系统时间显示正确，并支持多时区设置
  locales            # 本地化支持包，提供各种语言环境，用于设置系统语言和字符编码
  perl               # Perl 脚本解释器，部分工具脚本可能依赖 Perl
  #cron              # 定时任务调度工具，用于管理和执行定时任务（在docker中会反复调用并爆炸）
)

# 所需系统软件包列表（基础系统工具和常用工具）
dev_lib_packages=(
  # 图像格式支持开发库（Pillow 编译 / 高级格式依赖）
  libjpeg-dev        # JPEG 图像格式开发库（Pillow 的 JPEG 读写支持）
  zlib1g-dev         # zlib 压缩库开发包（PNG、gzip 等基础压缩支持，Pillow 必备）
  libpng-dev         # PNG 图像格式开发库（Pillow 的 PNG 读写核心依赖）
  libwebp-dev        # WebP 图像格式开发库（现代网页优化格式，Pillow 支持读写 WebP）
  libavif-dev        # AVIF 图像格式开发库（高压缩现代格式，pillow-avif-plugin 依赖它）
  libheif-dev        # HEIF/HEIC 图像格式开发库（苹果设备主流格式，pillow-heif 依赖它）
  # 图像优化 & 复杂文本布局支持
  libimagequant-dev  # libimagequant 开发包，提供高质量 PNG 调色板量化压缩
                     # Pillow 的 Image.quantize() 使用它，能大幅减小 PNG 文件体积且保持视觉质量
  libraqm-dev        # Raqm 库开发包，支持复杂脚本文本布局（阿拉伯文、泰文、印度文等右到左/复杂排版）
                     # Pillow 在处理多语言复杂文字时会用到，避免文字错位或渲染错误
)

large_font_packages=(
  fontconfig                 # 提供 fc-cache、fc-list 等命令
  fonts-noto-cjk             # Google Noto CJK 字体包，提供中日韩文字支持
  fonts-comic-neue           # Comic Neue（最接近 xkcd 的现代漫画字体）
  ttf-mscorefonts-installer  # Comic Sans MS（兼容性更好）
)

# 更新 apt 并安装所需软件包
# 执行更新
retry_apt_update

# 一次性安装全部包
# Install in phases: core -> essentials -> dev libs -> large
log_info "Installing core APT tools..."
missing_core=($(get_missing_packages ${core_apt_packages[@]}))
if [ -n "${missing_core[*]}" ]; then
  for pkg in "${missing_core[@]}"; do retry_apt_install_bulk "${pkg}"; done
fi

# 循环安装各软件包
#for pkg in "${apt_packages[@]}"; do
#  log_info "Installing linux packages individually with retries..."
#  retry_apt_install_bulk "${pkg}"
#done

# 使用 eatmydata 提高安装效率
# Now use eatmydata/aptitude for the rest
eatmydata aptitude --without-recommends -o APT::Get::Fix-Missing=true -y update || true  # Non-fatal update

# 一次性安装全部包
log_info "Installing essential packages..."
missing_essentials=($(get_missing_packages "${essential_packages[@]}"))
if [ -n "${missing_essentials[*]}" ]; then
  for pkg in "${missing_essentials[@]}"; do retry_apt_install_bulk "${pkg}"; done
fi

log_info "Installing dev lib packages..."
missing_dev_libs=($(get_missing_packages "${dev_lib_packages[@]}"))
if [ -n "${missing_dev_libs[*]}" ]; then
  for pkg in "${missing_dev_libs[@]}"; do retry_apt_install_bulk "${pkg}"; done
fi

log_info "Installing large font packages (optional phase)..."

# 预先同意微软字体安装协议 (核心修改)
if echo "${large_font_packages[*]}" | grep -q "ttf-mscorefonts-installer"; then
  log_info "Pre-accepting EULA for ttf-mscorefonts-installer..."
  echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | debconf-set-selections
fi

missing_large=($(get_missing_packages "${large_font_packages[@]}"))
if [ -n "${missing_large[*]}" ]; then
  for pkg in "${missing_large[@]}"; do retry_apt_install_bulk "${pkg}"; done
fi

# 刷新系统字体缓存
# Refresh fonts if installed
if command -v fc-cache &> /dev/null; then
  fc-cache -fv
fi

# 配置时区：复制指定时区文件到 /etc/localtime 并写入 /etc/timezone
ln -fs /usr/share/zoneinfo/${TZ} /etc/localtime
dpkg-reconfigure -f noninteractive tzdata
# 依赖 systemd 然而又不能要 cron
#timedatectl set-timezone ${TZ} || true
# 依赖 systemd 然而又不能要 cron
#timedatectl set-ntp true || true

# 比较当前时间与上海时间
compare_time() {
  current_time=$(date '+%Y-%m-%d %T')
  shanghai_time=$(TZ=${TZ} date '+%Y-%m-%d %T')
  echo "当前时间: ${current_time} <-> 上海时间: ${shanghai_time}"
}
compare_time

# 配置简体中文环境
sed -i 's/^# *\(zh_CN.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen zh_CN.UTF-8
update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 LANGUAGE=zh_CN.UTF-8 LC_CTYPE=zh_CN.UTF-8

# 将激活环境及 locale 配置写入配置文件中，保留长期有效
# 在 docker 非交互式容器中毫无意义，可以没有，但是我希望，这能帮助我理解
cat << '469138946ba5fa' | tee -a /etc/default/locale /etc/environment "${HOME}/.profile"
LANG=zh_CN.UTF-8
LC_ALL=zh_CN.UTF-8
LANGUAGE=zh_CN.UTF-8
LC_CTYPE=zh_CN.UTF-8
469138946ba5fa

# 获取当前 shell 名称
CURRENT_SHELL=$(basename "${SHELL}")

log_info "Detected shell: ${CURRENT_SHELL}"

case "${CURRENT_SHELL}" in
  bash)
    if ! grep -qEi 'LANG|LC_ALL|LANGUAGE|LC_CTYPE' "${HOME}/.bashrc"; then
      log_info "Initializing LANG|LC_ALL|LANGUAGE|LC_CTYPE for bash..."
      # 固化 LANG|LC_ALL|LANGUAGE|LC_CTYPE 环境
      # 在 docker 非交互式容器中毫无意义，可以没有，但是我希望，这能帮助我理解
      cat << '469138946ba5fa' | tee -a /etc/skel/.bashrc "${HOME}/.bashrc"
LANG=zh_CN.UTF-8
LC_ALL=zh_CN.UTF-8
LANGUAGE=zh_CN.UTF-8
LC_CTYPE=zh_CN.UTF-8
469138946ba5fa
    fi
    ;;
  zsh)
    if ! grep -qEi 'LANG|LC_ALL|LANGUAGE|LC_CTYPE' "${HOME}/.zshrc"; then
      log_info "Initializing LANG|LC_ALL|LANGUAGE|LC_CTYPE for zsh..."
      # 固化 LANG|LC_ALL|LANGUAGE|LC_CTYPE 环境
      # 在 docker 非交互式容器中毫无意义，可以没有，但是我希望，这能帮助我理解
      cat << '469138946ba5fa' | tee -a /etc/skel/.zshrc "${HOME}/.zshrc"
LANG=zh_CN.UTF-8
LC_ALL=zh_CN.UTF-8
LANGUAGE=zh_CN.UTF-8
LC_CTYPE=zh_CN.UTF-8
469138946ba5fa
    fi
    ;;
  *)
    log_error "Unsupported shell: ${CURRENT_SHELL}"
    exit 1
    ;;
esac

log_info "System initialization completed."
