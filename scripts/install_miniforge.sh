#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

log_info "Starting Miniforge environment setup..."

# Docker 提供的操作系统和架构信息
#export TARGETOS=${TARGETOS}
#export TARGETARCH=${TARGETARCH}

# Miniforge 安装路径
# export MAMBA_ROOT_PREFIX=/opt/Miniforge

# miniforge 软件源
# export CONDA_CHANNELS="${CONDA_CHANNELS:-defaults}"

# 初始化 Miniforge 环境
# export PATH=${PATH}:${MAMBA_ROOT_PREFIX}/bin
# 某些 linux 系统可能需要导入 Miniforge 的 lib 环境
# 如果你需要这个，就执行，之后可能还需要手动写入到 bash 或 zsh 的配置文件中，以持续生效
# 但是我不确定是不是所有的 linux 都会 lib 缺失，先注释吧
#export LD_LIBRARY_PATH=${MAMBA_ROOT_PREFIX}/lib:${LD_LIBRARY_PATH}

# 新增函数：执行 Miniforge 安装，备用策略，防止失败
install_miniforge() {
    local installer_path="$1"
    local install_prefix="$2"

    log_info "Attempting Miniforge installation with current script logic..."
    
    # 尝试第一次安装 (使用原始脚本，即 bs=N)
    if bash "${installer_path}" -b -f -p "${install_prefix}"; then
        log_info "Miniforge installation successful on first attempt."
        return 0
    else
        local first_attempt_status=$?
        log_warning "First installation attempt failed with status ${first_attempt_status}."
        
        # 仅在 Linux 上且第一次安装失败时尝试修复
        if [[ "${TARGETOS}" == "Linux" ]]; then
            log_warning "Applying patch: modifying 'bs=' to 'ibs=' in the installer script to bypass known 'dd' bug..."
            
            # 使用 sed 在临时文件中进行替换。注意：需要对文件进行修改
            # 1. 备份原始文件（可选，但安全）
            # cp "${installer_path}" "${installer_path}.bak"
            
            # 2. 在脚本中执行替换操作
            # \1 捕获前一个 dd if="$THIS_PATH"
            # s/bs=/ibs=/ 替换 bs= 为 ibs=
            # g 全局替换所有匹配项 (虽然只有三处)
            sed -i.bak -E 's/(dd if="\$THIS_PATH" )bs=/\1ibs=/g' "${installer_path}"
            
            # 检查替换是否成功 (如果文件存在 .bak 副本，说明 sed 成功运行)
            if [[ ! -f "${installer_path}.bak" ]]; then
                log_error "Failed to modify installer script using sed. Aborting patch attempt."
                return 1
            fi

            log_info "Retrying Miniforge installation with patched script (ibs=N)..."
            
            # 尝试第二次安装 (使用修改后的脚本，即 ibs=N)
            if bash "${installer_path}" -b -f -p "${install_prefix}"; then
                log_info "Miniforge installation successful after applying 'ibs=' patch."
                # 理论上可以清理 .bak 文件： rm -f "${installer_path}.bak"
                return 0
            else
                local second_attempt_status=$?
                log_error "Second installation attempt (patched) failed with status ${second_attempt_status}. Installation failed permanently."
                # 恢复原始文件 (可选)
                # mv "${installer_path}.bak" "${installer_path}"
                return 1
            fi
        fi

        log_error "Installation failed and no patching was attempted (or patching failed). Status: ${first_attempt_status}"
        return 1
    fi
}

# GitHub 项目 URI
URI="conda-forge/miniforge"

# 获取最新版本
VERSION=$(curl -sL "https://github.com/${URI}/releases" | grep -Eo '/releases/tag/[^"]+' | awk -F'/tag/' '{print $2}' | head -n 1)
log_info "Latest version: ${VERSION}"

# 限定范围以后有其他的再加
case "${TARGETOS}" in
  linux)
    TARGETOS="Linux"
    case "${TARGETARCH}" in
      arm64)
        TARGETARCH="aarch64"
        ;;
      amd64)
        TARGETARCH="x86_64"
        ;;
      *)
        log_error "Unsupported architecture: ${TARGETARCH}"
        exit 1
        ;;
    esac
    ;;
  # 这本身不用于docker只是用于记录这段代码可能永远不会生效
  darwin)
    TARGETOS="MacOSX"
    case "${TARGETARCH}" in
      arm64)
        TARGETARCH="arm64"
        ;;
      amd64)
        TARGETARCH="x86_64"
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

# 拼接下载链接和校验码链接
TARGET_FILE="Miniforge3-${VERSION}-${TARGETOS}-${TARGETARCH}.sh"
SHA256_FILE="${TARGET_FILE}.sha256"
URI_DOWNLOAD="https://github.com/${URI}/releases/download/${VERSION}/${TARGET_FILE}"
URI_SHA256="https://github.com/${URI}/releases/download/${VERSION}/${SHA256_FILE}"
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

# 创建安装目录
log_info "Installing Miniforge..."
mkdir -pv ${MAMBA_ROOT_PREFIX}
chmod -Rv a+x ${MAMBA_ROOT_PREFIX}

# 设置安装目录权限
case "${TARGETOS}" in
  Linux)
    # Linux 通常用户组为用户名
    chown -Rv $(whoami):$(whoami) ${MAMBA_ROOT_PREFIX}
    ;;
  # 这本身不用于docker只是用于记录这段代码可能永远不会生效
  MacOSX)
    # macOS 使用 "admin" 作为用户组
    chown -Rv $(whoami):admin ${MAMBA_ROOT_PREFIX}
    ;;
  *)
    log_error "Unsupported TARGETOS: ${TARGETOS}"
    exit 1
    ;;
esac

# 赋予执行权限 (虽然是目录，但保险起见)
chmod -R 755 ${MAMBA_ROOT_PREFIX}

# 安装 Miniforge
#bash "/tmp/${TARGET_FILE}" -b -f -p ${MAMBA_ROOT_PREFIX}
# 最新版本 ubuntu 25.10 rolling 有一个bug导致脚本自解压行为发生了改变即偏移量计算产生错误进而导致 dd 命令数据提取不完整，导致整个脚本安装报错
# bug 报告 https://bugs.launchpad.net/ubuntu/+source/makeself/+bug/2125535
# 执行安装函数，实现兼容性测试，为了修补官方bug，更确切的说是绕过，修改 dd 参数 bs 为 ibs 让 dd 自动调整提取数据，我觉得风险极高，但是值得试试
# 修改方法 https://github.com/conda-forge/miniforge/issues/824#issuecomment-3435506619
if ! install_miniforge "/tmp/${TARGET_FILE}" "${MAMBA_ROOT_PREFIX}"; then
    log_error "Fatal: Miniforge installation failed after all compatibility attempts."
    exit 1
fi

# 更新 Mamba 和 Conda
mamba update -n base -c ${CONDA_CHANNELS} mamba -y
mamba update -n base -c ${CONDA_CHANNELS} conda -y

# 将激活环境写入配置文件中，保留长期有效
# 在 docker 非交互式容器中毫无意义，可以没有，但是我希望，这能帮助我理解
cat << 469138946ba5fa | tee -a /etc/environment "${HOME}/.profile"
. /opt/Miniforge/etc/profile.d/conda.sh
469138946ba5fa

# 获取当前 shell 名称
CURRENT_SHELL=$(basename "${SHELL}")

log_info "Detected shell: ${CURRENT_SHELL}"

case "${CURRENT_SHELL}" in
  bash)
    if ! grep -q "conda activate ${CONDA_PY_ENV}" "${HOME}/.bashrc"; then
      log_info "Initializing ${CONDA_PY_ENV} for bash..."
      # 固化 ${CONDA_PY_ENV} 环境
      # 在 docker 非交互式容器中毫无意义，可以没有，但是我希望，这能帮助我理解
      echo ". /opt/Miniforge/etc/profile.d/conda.sh" | tee -a /etc/skel/.bashrc "${HOME}/.bashrc"
    fi
    ;;
  zsh)
    if ! grep -q "conda activate ${CONDA_PY_ENV}" "${HOME}/.zshrc"; then
      log_info "Initializing ${CONDA_PY_ENV} for zsh..."
      # 固化 ${CONDA_PY_ENV} 环境
      # 在 docker 非交互式容器中毫无意义，可以没有，但是我希望，这能帮助我理解
      echo ". /opt/Miniforge/etc/profile.d/conda.sh" | tee -a /etc/skel/.zshrc "${HOME}/.zshrc"
    fi
    ;;
  *)
    log_error "Unsupported shell: ${CURRENT_SHELL}"
    exit 1
    ;;
esac

log_info "Miniforge setup is complete."
mamba --version
