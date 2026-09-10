#!/usr/bin/env bash
set -euo pipefail

# 加防误 source 保护
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "This file is a library. Do not execute directly." >&2
  echo exit 1
fi

# 定义彩色日志输出函数
DEBUG='\033[0;37m'   # 灰色
INFO='\033[0;34m'    # 蓝色
SUCCESS='\033[0;32m' # 绿色
WARNING='\033[0;33m' # 黄色
ERROR='\033[0;31m'   # 红色
CRITICAL='\033[1;41m' # 红底白字
NC='\033[0m'         # 无色，重置颜色

# 日志函数
log_debug()   { echo -e "${DEBUG}[DEBUG] $(date '+%F_%T') - $1${NC}" >&2; }
log_info()    { echo -e "${INFO}[INFO] $(date '+%F_%T') - $1${NC}" >&2; }
log_success() { echo -e "${SUCCESS}[SUCCESS] $(date '+%F_%T') - $1${NC}" >&2; }
log_warning() { echo -e "${WARNING}[WARNING] $(date '+%F_%T') - $1${NC}" >&2; }
log_error()   { echo -e "${ERROR}[ERROR] $(date '+%F_%T') - $1${NC}" >&2; }
log_critical(){ echo -e "${CRITICAL}[CRITICAL] $(date '+%F_%T') - $1${NC}" >&2; }

# 检查命令是否存在
command_exists() {
  command -v "$1" >/dev/null 2>&1
}