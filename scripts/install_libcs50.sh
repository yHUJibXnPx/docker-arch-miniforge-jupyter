#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

log_info "Starting libcs50 environment setup..."

# **下载并解压 libcs50 源码**  
# 参考：[cs50/libcs50 - From Source (Linux and Mac)](https://github.com/cs50/libcs50#from-source-linux-and-mac)
pushd /tmp
curl -L -C - --retry 3 --retry-delay 5 --progress-bar \
  -o libcs50-11.0.3.tar.gz \
  https://github.com/cs50/libcs50/archive/refs/tags/v11.0.3.tar.gz
tar zxvf libcs50-11.0.3.tar.gz && rm -f libcs50-11.0.3.tar.gz
pushd libcs50-11.0.3
make install
popd
#rm -frv libcs50-11.0.3
popd

log_info "libcs50 setup is complete."
ls -al /usr/local/lib/libcs50.so* /usr/local/include/cs50.h