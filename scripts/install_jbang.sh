#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

log_info "Setting up JBang and configuring Jupyter Java Kernel..."

# Miniforge 安装路径
# export MAMBA_ROOT_PREFIX=/opt/Miniforge

# miniforge 软件源
# export CONDA_CHANNELS="${CONDA_CHANNELS:-defaults}"

# 初始化 Miniforge 环境
# export PATH=${MAMBA_ROOT_PREFIX}/bin:${PATH}
# 某些 linux 系统可能需要导入 Miniforge 的 lib 环境
# 如果你需要这个，就执行，之后可能还需要手动写入到 bash 或 zsh 的配置文件中，以持续生效
# 但是我不确定是不是所有的 linux 都会 lib 缺失，先注释吧
#export LD_LIBRARY_PATH=${MAMBA_ROOT_PREFIX}/lib:${LD_LIBRARY_PATH}

# 指定 python 版本
#export PY_VERSION=3.12.10
#export CONDA_PY_ENV=py${PY_VERSION}

# jbang 环境
# export PATH="${PATH}:${HOME}/.jbang/bin"

# 激活${CONDA_PY_ENV}
log_info "Activate ${CONDA_PY_ENV} env..."
# 明确激活 ${CONDA_PY_ENV}，确保非交互式环境变量生效，规避 ADDR2LINE: unbound variable
# 取消 set -u（如果你之前开启了严格模式）
set +u
# source conda 环境
. "${MAMBA_ROOT_PREFIX}/etc/profile.d/conda.sh"
conda activate "${CONDA_PY_ENV}"
set -u

# 安装 JBang
curl -Ls https://sh.jbang.dev | bash -s - app setup

# 配置信任与 Catalog
jbang trust add https://github.com/jupyter-java/
jbang trust add https://repo1.maven.org/
jbang catalog add --force --name jupyter-java https://github.com/jupyter-java/jbang-catalog/raw/main/jbang-catalog.json

# 安装内核 Spec
log_info "Installing IJava kernel spec..."
jbang install-kernel@jupyter-java

# -----------------------------------------------------------------------------
# 核心改进：全动态依赖提取与预热
# -----------------------------------------------------------------------------
log_info "Dynamically warming up JBang cache from kernel.json..."

KERNEL_JSON="${HOME}/.local/share/jupyter/kernels/jjava/kernel.json"

if [ -f "$KERNEL_JSON" ]; then
  # 动态提取所有坐标
  # 1. 找包含 ":" 的字符串
  # 2. 去掉 JBang 的 %{deps: ... } 包装
  MAP_DEPS=$(jq -r '.argv[] | select(contains(":")) | gsub("^%\\{deps:|\\}$"; "")' "$KERNEL_JSON")
  
  for dep in $MAP_DEPS; do
    log_info "Pre-caching dependency: $dep"
    # 使用 --fresh 确保元数据完整下载
    jbang info classpath --fresh "$dep" > /dev/null || log_warn "Failed to resolve $dep, but continuing..."
  done
else
    log_error "Kernel JSON not found, skipping dynamic pre-cache."
    exit 1
fi

# -----------------------------------------------------------------------------
# 稳健的离线内核生成 (只插入 --offline 参数)
# -----------------------------------------------------------------------------
SRC_KERNEL_DIR="${HOME}/.local/share/jupyter/kernels/jjava"
OFFLINE_KERNEL_DIR="${HOME}/.local/share/jupyter/kernels/jjava-offline"

log_info "Creating Offline Kernel clone..."
mkdir -p "$OFFLINE_KERNEL_DIR"

cp -r "${SRC_KERNEL_DIR}/"* "$OFFLINE_KERNEL_DIR/"

# 注入 --offline 到 argv[1] 位置
jq '.display_name = "Java Offline (JJava/j!)" | 
  .argv = [.argv[0], "--offline"] + .argv[1:] | 
  .env += {"JBANG_OFFLINE": "true"}' \
  "${SRC_KERNEL_DIR}/kernel.json" > "${OFFLINE_KERNEL_DIR}/kernel.json"

log_success "Offline kernel configured and localized."

# 验证
CACHE_SIZE=$(du -sh "${HOME}/.jbang/cache" 2>/dev/null | cut -f1 || echo "0")
log_success "JBang cache size: ${CACHE_SIZE}"
jupyter-kernelspec list