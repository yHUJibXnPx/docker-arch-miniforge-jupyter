#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

log_info "Setting up Gophernotes and configuring Jupyter Go Kernel..."

# Miniforge 安装路径
#export MAMBA_ROOT_PREFIX=/opt/Miniforge

# miniforge 软件源
#export CONDA_CHANNELS="${CONDA_CHANNELS:-defaults}"

# 初始化 Miniforge 环境
#export PATH=${MAMBA_ROOT_PREFIX}/bin:${PATH}
# 某些 linux 系统可能需要导入 Miniforge 的 lib 环境
# 如果你需要这个，就执行，之后可能还需要手动写入到 bash 或 zsh 的配置文件中，以持续生效
# 但是我不确定是不是所有的 linux 都会 lib 缺失，先注释吧
#export LD_LIBRARY_PATH=${MAMBA_ROOT_PREFIX}/lib:${LD_LIBRARY_PATH}

# 指定 python 版本
#export PY_VERSION=3.12.10
#export CONDA_PY_ENV=py${PY_VERSION}

# 激活${CONDA_PY_ENV}
log_info "Activate ${CONDA_PY_ENV} env..."
# 明确激活 ${CONDA_PY_ENV}，确保非交互式环境变量生效，规避 ADDR2LINE: unbound variable
# 取消 set -u（如果你之前开启了严格模式）
set +u
# source conda 环境
. "${MAMBA_ROOT_PREFIX}/etc/profile.d/conda.sh"
conda activate "${CONDA_PY_ENV}"
set -u

# pip 软件源
#export PIP_CHANNELS="${PIP_CHANNELS:-https://pypi.org/simple}"

# GoNB 环境
#export GOROOT="/opt/go"
#export GOPATH="${HOME}/go"
#export PATH="${PATH}:${GOROOT}/bin:${GOPATH}/bin"
# https://goproxy.cn,direct
#export GOPROXY='https://proxy.golang.org,direct'
# sum.golang.google.cn
#export GOSUMDB=off

# 安装 GoNB
# 显式安装 gonb (加上版本号确保能拉取到)
go install github.com/janpfeifer/gonb@latest

# 安装自动导包工具
go install golang.org/x/tools/cmd/goimports@latest

# 安装 Go 语言服务器
go install golang.org/x/tools/gopls@latest

# 执行 gonb 自带的安装命令
gonb --install

log_info "GoNB setup completed."
jupyter-kernelspec list