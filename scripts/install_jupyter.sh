#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

log_info "Starting Jupyter environment setup..."

# Miniforge 安装路径
#export MAMBA_ROOT_PREFIX=/opt/Miniforge

# miniforge 软件源
#export CONDA_CHANNELS="${CONDA_CHANNELS:-defaults}"
#export PIP_CHANNELS='https://pypi.org/simple'

# 初始化 Miniforge 环境
#export PATH=${PATH}:${MAMBA_ROOT_PREFIX}/bin

# 某些 linux 系统可能需要导入 Miniforge 的 lib 环境
# 如果你需要这个，就执行，之后可能还需要手动写入到 bash 或 zsh 的配置文件中，以持续生效
# 但是我不确定是不是所有的 linux 都会 lib 缺失，先注释吧
#export LD_LIBRARY_PATH=${MAMBA_ROOT_PREFIX}/lib:${LD_LIBRARY_PATH}

# 指定 python 版本
#export PY_VERSION=3.12.10
#export CONDA_PY_ENV=py${PY_VERSION}
#export CONDA_PREFIX=${MAMBA_ROOT_PREFIX}/envs/${CONDA_PY_ENV}
#export PATH=${PATH}:${CONDA_PREFIX}/bin:${MAMBA_ROOT_PREFIX}/bin:${HOME}/.jbang/bin:${JAVA_HOME}/bin

# conda 包安装带重试逻辑
retry_conda_install_bulk() {
  local retries=3
  local sleep_seconds=2
  local pkgs=("$@")
  for ((i=1; i<=retries; i++)); do
    log_info "Installing conda packages in bulk (attempt ${i}/${retries})"
    if mamba install "${pkgs[@]}" -c "${CONDA_CHANNELS}" -y; then
      log_info "All conda packages installed successfully."
      return 0
    else
      log_warning "Failed attempt ${i} to install conda packages, retrying after ${sleep_seconds}s..."
      sleep ${sleep_seconds}
    fi
  done
  log_error "Failed to install conda packages after ${retries} attempts."
  exit 1
}

# pip 包安装带重试逻辑
retry_pip_install_bulk() {
  local retries=3
  local sleep_seconds=2
  local pkgs=("$@")
  for ((i=1; i<=retries; i++)); do
    log_info "Installing pip packages in bulk (attempt ${i}/${retries})"
    if python -m pip install --no-cache-dir -v "${pkgs[@]}" --break-system-packages -i ${PIP_CHANNELS}; then
      log_info "All pip packages installed successfully."
      return 0
    else
      log_warning "Failed attempt ${i} to install pip packages, retrying after ${sleep_seconds}s..."
      sleep ${sleep_seconds}
    fi
  done
  log_error "Failed to install pip packages after ${retries} attempts."
  exit 1
}

# pip 包重安装带重试逻辑
retry_pip_force_reinstall_bulk() {
  local retries=3
  local sleep_seconds=2
  local pkgs=("$@")
  for ((i=1; i<=retries; i++)); do
    log_info "Reinstalling pip packages in bulk (attempt ${i}/${retries})"
    if python -m pip install --force-reinstall -v "${pkgs[@]}" --break-system-packages -i ${PIP_CHANNELS}; then
      log_info "All pip packages reinstalling successfully."
      return 0
    else
      log_warning "Failed attempt ${i} to reinstalling pip packages, retrying after ${sleep_seconds}s..."
      sleep ${sleep_seconds}
    fi
  done
  log_error "Failed to reinstalling pip packages after ${retries} attempts."
  exit 1
}

# 所需软件包列表
conda_packages=(
  # cling 类别：为 Jupyter 提供 C++ 交互式内核及其依赖
  #xeus-cling                      # 基于 xeus 的 C++ 内核，可在 Jupyter 中运行 C++ 代码
  # GoNB 类别：为 Jupyter 提供 Go 交互式内核及其依赖
  #go
  # 压缩类别
  zlib                            # 压缩库，各种软件包可能依赖它
  # jupyter 类别
  nb_conda_kernels                # 允许自动检测和使用 conda 环境中的内核
)

pip_packages=(
  # jupyter 类别：构建完整的 Jupyter 环境及扩展
  jupyterlab                      # 下一代 Jupyter 用户界面，支持交互式笔记本和代码
  notebook                        # 经典 Jupyter Notebook 应用
  voila                           # 可将 Jupyter 笔记本转换为独立的 Web 应用
  ipywidgets                      # 为笔记本提供交互式控件（HTML widgets）
  qtconsole                       # 基于 Qt 的 Jupyter 控制台，提供终端式界面
  jupyter_contrib_nbextensions    # 社区贡献的 Notebook 扩展集合，可增强功能
  jupyterlab-git                  # 在 JupyterLab 中集成 Git 版本控制功能
  jupyterlab-dash                 # 允许在 JupyterLab 中嵌入和交互使用 Dash 应用

  # data 类别：用于数值计算、数据处理和可视化
  numpy                           # 数组计算基础库，为后续科学计算提供支持
  scipy                           # 科学计算库，包含大量算法和数学工具
  pandas                          # 数据分析和数据结构处理工具
  matplotlib                      # 绘图和数据可视化库

  # machine 类别：机器学习
  seaborn                         # 基于 matplotlib 的统计数据可视化库
  scikit-learn                    # 机器学习库，提供分类、回归、聚类等算法
  tensorflow                      # 由 Google 开发的一个可商业化的开源深度学习框架

  # network 类别：与网络请求、爬虫及数据库交互相关
  beautifulsoup4                  # HTML/XML 解析库，用于网页数据爬取和处理
  requests                        # 简单优雅的 HTTP 请求库
  SQLAlchemy                      # SQL 工具包及 ORM，用于数据库交互
  retrying                        # 帮助实现函数重试机制的库，适用于网络请求等场景
  "httpx[socks]"                  # 支持 SOCKS 代理的 httpx
  socksio                         # httpx 处理 SOCKS 协议的后端实现
  jupyter-c-kernel                # 简单的 C/C++ Jupyter 内核（编译型）
                                  # 属于“保底”方案，不依赖 cling，稳定性较高
                                  # 适合运行标准 C/C++ 代码，但交互能力有限

  # 绘图增强 & 图像处理类别（Pillow 及其插件）
  Pillow                          # Python Imaging Library (PIL) 分支，图像处理核心库
                                  # 用于 matplotlib 保存图片、图像读写、格式转换、简单编辑等

  pillow-avif-plugin              # 为 Pillow 添加 AVIF 格式读写支持
                                  # AVIF 是现代高效图像格式（比 JPEG/WebP 压缩更好）
                                  # 常用于网页优化、低体积高质量图像存储
                                  # 需要 libavif 系统依赖（通常 apt install libavif-dev）

  pillow-heif                     # 为 Pillow 添加 HEIF/HEIC 格式支持（苹果设备常用）
                                  # 可直接读取 iPhone 拍摄的 .heic 照片
                                  # 常用于手机照片处理与跨平台兼容

  ffmpeg-python                   # FFmpeg 的 Python 封装库
                                  # 用于音视频转码、裁剪、提取音轨、格式转换等操作
                                  # 本身依赖系统已安装 ffmpeg 可执行程序

  imagehash                       # 感知哈希（Perceptual Hash）图像处理库
                                  # 用于图像相似度比较、重复图片检测、内容去重
                                  # 常用于图库管理、爬虫图片过滤等场景

  opencv-python                   # OpenCV 官方 Python 绑定
                                  # 提供计算机视觉、图像处理、视频分析等功能
                                  # 支持人脸检测、目标识别、摄像头读取等任务

  scikit-image                    # 基于 NumPy/SciPy 的图像处理库
                                  # 提供滤波、边缘检测、分割、形态学等算法
                                  # 更偏科研与算法实验，常与 OpenCV 搭配使用

  tqdm                            # 轻量级进度条库
                                  # 可为循环、下载、训练过程显示实时进度
                                  # 支持终端、Jupyter Notebook 等多种环境
)

# 备用功能，所需强制重装安装包
pip_force_packages=(
  setuptools                      # 生成 console_scripts entrypoints
  wheel                           # 确保正确的 wheel 安装机制
)

# Miniforge 创建最新的 py 环境
# 拼接下载链接和校验码链接
log_info "Detected beta release version..."
if [[ -n "${PY_VERSION:-}" ]]; then
  log_info "Using version from environment/ARG: ${PY_VERSION}"
else
  log_info "PY_VERSION is empty, searching for the latest version..."
  # 获取搜索结果
  PY_VERSIONS_LIST=$(mamba repoquery search python -c "${CONDA_CHANNELS}")
  # 精准抓取：grep -w 匹配完整单词 python，awk 确保版本号是以数字开头
  PY_VERSION=$(echo "${PY_VERSIONS_LIST}" | grep -w "python" | awk '$2 ~ /^[0-9]/ {print $2}' | sort -V | tail -n 1)
  if [[ -z "${PY_VERSION}" ]]; then
    log_error "Could not find any valid python version in channels!"
    exit 1
  fi
  log_info "Automatically detected latest version: ${PY_VERSION}"
fi
log_info "latest python version "${PY_VERSION}

# 创建 Conda 环境
# mamba 安装 python ${PY_VERSION} 版本并将环境命名为 ${CONDA_PY_ENV}
log_info "Creating Conda environment ${CONDA_PY_ENV} with Python ${PY_VERSION}..."
mamba create -n ${CONDA_PY_ENV} python=${PY_VERSION} -c "${CONDA_CHANNELS}" -y

# 激活${CONDA_PY_ENV}
log_info "Activate ${CONDA_PY_ENV} env..."
# 明确激活 ${CONDA_PY_ENV}，确保非交互式环境变量生效，规避 ADDR2LINE: unbound variable
# 取消 set -u（之前开启了严格模式）
set +u
# source conda 环境
. "${MAMBA_ROOT_PREFIX}/etc/profile.d/conda.sh"
conda activate "${CONDA_PY_ENV}"
set -u

# 一次性安装全部包
log_info "Installing conda packages individually with retries..."
retry_conda_install_bulk "${conda_packages[@]}"

# 循环安装各软件包
#log_info "Installing conda packages individually with retries..."
#for pkg in "${conda_packages[@]}"; do
#  retry_conda_install_bulk "${pkg}"
#done

# 更新 pip 工具包
python -m pip install --no-cache-dir -v --upgrade pip --break-system-packages -i ${PIP_CHANNELS}

# 一次性安装全部包
log_info "Installing pip packages individually with retries..."
retry_pip_install_bulk "${pip_packages[@]}"

#log_info "Installing pip packages individually with retries..."
#for pkg in "${pip_packages[@]}"; do
#  retry_pip_install_bulk "${pkg}"
#done

# 安装 Jupyter-C-Kernel (保底方案)
# 这会在 kernelspec 中注册一个 "C++ (gcc)"，即使 xeus-cpp 挂了，这个也能用
log_info "Installing Jupyter C Kernel (Fallback)..."
# 原来的写法
# install_c_kernel --user

# 更稳健的写法：显式调用 Python 模块（如果该包支持）或者打印位置
log_info "Registering Jupyter C Kernel..."
if command -v install_c_kernel &> /dev/null; then
  install_c_kernel --user
else
  log_error "install_c_kernel command not found! verifying pip install..."
  # 尝试用 python 直接调用模块（备选方案，如果 entrypoint 生成失败）
  # jupyter-c-kernel 的源码结构其实是一个简单的 install_c_kernel.py
  # 但通常 entrypoint 是最稳的。
  exit 1
fi

# 备用功能，补丁修复: 强制重新安装 setuptools, wheel，确保 jupyter 命令正确生成
log_info "Reinstalling setuptools and wheel to fix entrypoints..."
retry_pip_force_reinstall_bulk "${pip_force_packages[@]}"

#log_info "Reinstalling setuptools and wheel to fix entrypoints..."
#for pkg in "${pip_force_packages[@]}"; do
#  retry_pip_force_reinstall_bulk "${pkg}"
#done

# 安装 Xeus-Cpp (现代 C++ 交互式内核)
# 动态探测架构并选择对应的 GCC 编译器套件
# 目的：在 conda 环境内提供完整的 C++ 标准库头文件，隔离宿主机(Ubuntu Rolling)可能过新的 GCC 版本
ARCH=$(uname -m)
COMPILER_PKG=""

case "${ARCH}" in
  x86_64)
    log_info "Detected x86_64 architecture. Using gxx_linux-64..."
    COMPILER_PKG="gxx_linux-64"
    ;;
  aarch64)
    log_info "Detected aarch64 (ARM64) architecture. Using gxx_linux-aarch64..."
    COMPILER_PKG="gxx_linux-aarch64"
    ;;
  *)
    log_error "Unsupported architecture: ${ARCH}"
    exit 1
    ;;
esac

log_info "Creating dedicated C++ environment (jupyter-cpp) with xeus-cpp..."

# 创建一个独立环境 jupyter-cpp
# 同时安装 xeus-cpp 和 编译器(COMPILER_PKG)
# - xeus-cpp: 基于 clang-repl 的现代内核
# - ${COMPILER_PKG}: 强制使用 conda 提供的 gcc 头文件，避免 ABI 冲突
# - nlohmann_json: 常用 C++ 库，方便测试
mamba create -n jupyter-cpp xeus-cpp "${COMPILER_PKG}" nlohmann_json -c conda-forge -y

# 注意：因为安装了 nb_conda_kernels，主环境的 Jupyter 会自动扫描到
# 这个名为 "jupyter-cpp" 的环境，并将其显示为 "Python [jupyter-cpp]" (如果是py) 
# 或 "C++17/20" (由 xeus-cpp 提供)

# -----------------------------------------------------------
# Shell 环境配置
# -----------------------------------------------------------

# 重新激活主环境（以防万一）
# 激活${CONDA_PY_ENV}
log_info "Activate ${CONDA_PY_ENV} env..."
# 明确激活 ${CONDA_PY_ENV}，确保非交互式环境变量生效，规避 ADDR2LINE: unbound variable
# 取消 set -u（如果你之前开启了严格模式）
set +u
# source conda 环境
. "${MAMBA_ROOT_PREFIX}/etc/profile.d/conda.sh"
conda activate "${CONDA_PY_ENV}"
set -u

# 将激活环境写入配置文件中，保留长期有效
# 在 docker 非交互式容器中毫无意义，可以没有，但是我希望，这能帮助我理解
cat << 469138946ba5fa | tee -a /etc/environment "${HOME}/.profile"
conda activate ${CONDA_PY_ENV}
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
      echo "conda activate ${CONDA_PY_ENV}" | tee -a /etc/skel/.bashrc "${HOME}/.bashrc"
    fi
    ;;
  zsh)
    if ! grep -q "conda activate ${CONDA_PY_ENV}" "${HOME}/.zshrc"; then
      log_info "Initializing ${CONDA_PY_ENV} for zsh..."
      # 固化 ${CONDA_PY_ENV} 环境
      # 在 docker 非交互式容器中毫无意义，可以没有，但是我希望，这能帮助我理解
      echo "conda activate ${CONDA_PY_ENV}" | tee -a /etc/skel/.zshrc "${HOME}/.zshrc"
    fi
    ;;
  *)
    log_error "Unsupported shell: ${CURRENT_SHELL}"
    exit 1
    ;;
esac

log_info "Jupyter setup is complete."
jupyter-kernelspec list
jupyter --version
