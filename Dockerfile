# === 第一阶段：构建工坊 ===
# ubuntu 滚动版，追求新颖，不稳定
FROM docker.io/library/ubuntu:rolling AS builder
# 妥协，向失败的人生致敬🫡
#FROM docker.io/library/ubuntu:latest AS builder

# 构建参数，只有构建阶段有效，构建完成后消失
# init_system.sh 所需临时环境变量
ARG DEBIAN_FRONTEND=noninteractive
ARG TZ='Asia/Shanghai'
# Docker 提供的环境比如 linux/arm64 linux/arm64 linux arm64
ARG BUILDPLATFORM
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH
# install_miniforge.sh install_jupyter.sh 所需临时环境变量
# 获取 miniforge PY_VERSION 版本，记得必须将第二阶段版本也改为一致
ARG CONDA_CHANNELS=defaults
ARG PIP_CHANNELS='https://pypi.org/simple'
ARG PY_VERSION=3.13.15
ARG CONDA_PY_ENV=py${PY_VERSION}
ARG CONDA_PROMPT_MODIFIER=(${CONDA_PY_ENV})
ARG CONDA_DEFAULT_ENV=${CONDA_PY_ENV}
# install_go.sh 所需环境变量
# https://goproxy.cn,direct
ARG GOPROXY='https://proxy.golang.org,direct'
# sum.golang.google.cn
ARG GOSUMDB=off
# ENV 需要固化的临时环境
ARG BUILD_HOME=/root
ARG MAMBA_ROOT_PREFIX=/opt/Miniforge
ARG _CONDA_ROOT=${MAMBA_ROOT_PREFIX}
ARG CONDA_PYTHON_EXE=${MAMBA_ROOT_PREFIX}/bin/python
# 某些 linux 系统可能需要导入 Miniforge 的 lib 环境
# 如果你需要这个，就执行，之后可能还需要手动写入到 bash 或 zsh 的配置文件中，以持续生效
# 但是我不确定是不是所有的 linux 都会 lib 缺失，先注释吧
#ARG LD_LIBRARY_PATH=${MAMBA_ROOT_PREFIX}/lib:${LD_LIBRARY_PATH:-}
ARG CONDA_PREFIX=${MAMBA_ROOT_PREFIX}/envs/${CONDA_PY_ENV}
ARG CONDA_EXE=${MAMBA_ROOT_PREFIX}/bin/conda
ARG _CONDA_EXE=${CONDA_EXE}
ARG JAVA_HOME=${BUILD_HOME}/.jbang/currentjdk
ARG CLASSPATH=.:${JAVA_HOME}/lib
ARG GOROOT="/opt/go"
ARG GOPATH="${BUILD_HOME}/go"
# [核心修改] 修改 PATH 定义
# 1. 优先加入 ${CONDA_PY_ENV}/bin：确保直接输入 python/jupyter 时调用的是主环境
# 2. 其次是 Miniforge/bin：确保能调用 conda/mamba
# 3. 再次是 Java/Jbang
# 4. 最后是系统原有的 PATH
ARG PATH=${PATH}:${MAMBA_ROOT_PREFIX}/envs/${CONDA_PY_ENV}/bin:${MAMBA_ROOT_PREFIX}/condabin:${MAMBA_ROOT_PREFIX}/bin:${BUILD_HOME}/.jbang/bin:${JAVA_HOME}/bin:${GOROOT}/bin:${GOPATH}/bin

# shell 其他环境
ARG SHELL=/bin/bash \
    LANG=zh_CN.UTF-8 \
    LC_ALL=zh_CN.UTF-8 \
    LANGUAGE=zh_CN.UTF-8 \
    LC_CTYPE=zh_CN.UTF-8

# 添加常用LABEL（根据需要修改）添加标题 版本 作者 代码仓库 镜像说明，方便优化
LABEL org.opencontainers.image.description="miniforge 安装 jupyter notebook 封装特殊需求自用 python 测试容器." \
      org.opencontainers.image.title="Miniforge Jupyter" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.authors="yHUJibXnPx <bXnPxyHUJi@outlook.com>" \
      org.opencontainers.image.source="https://github.com/yHUJibXnPx/docker-arch-miniforge-jupyter" \
      org.opencontainers.image.licenses="MIT"

# 复制所有脚本到 /usr/local/bin（保持工作目录干净）
# 执行安装与配置脚本（全部以 root 执行）
# 并用 --mount=type=bind,source=scripts,target=/usr/local/src/scripts 替代等效且不会产生层级
#COPY scripts/ /usr/local/src/scripts

# 执行 初始化 安装 清理 三大流程
# 移除残留脚本 init_system.sh install_miniforge.sh install_jupyter.sh install_jbang.sh install_jdk.sh clean.sh
# 保留日志脚本 common.sh
# 启动脚本 start_jupyter.sh
# analyze_size.sh 检查安装前、后与清理后的镜像大小记录变化，不过镜像似乎无法优化了，😮‍💨
# 总结：似乎镜像无法优化了，已到绝处，无法逢生，在绝对的力量面前任何优化手段都毫无意义😮‍💨
# analyze_size.sh after-install before-install
# analyze_size.sh after-clean after-install
RUN --mount=type=bind,source=scripts,target=/usr/local/src/scripts \
    echo "build=${BUILDPLATFORM} target=${TARGETPLATFORM} os=${TARGETOS} arch=${TARGETARCH}" && \
    cp -fv /usr/local/src/scripts/*.sh /usr/local/bin/ && \
    cd /usr/local/bin/ && \
    chmod -v a+x *.sh && \
    analyze_size.sh before-install && \
    init_system.sh && \
    install_supercronic.sh && \
    install_libcs50.sh && \
    install_miniforge.sh && \
    install_jupyter.sh && \
    install_jdk.sh && \
    install_jbang.sh && \
    install_go.sh && \
    install_gonb.sh && \
    analyze_size.sh after-install && \
    clean.sh && \
    rm -fv init_system.sh install_supercronic.sh install_miniforge.sh install_jupyter.sh install_libcs50.sh install_jdk.sh install_jbang.sh install_go.sh install_gonb.sh clean.sh && \
    analyze_size.sh after-clean

# === 第二阶段：真空封存 (终极单层) ===
# scratch 是一个绝对为空的镜像
FROM scratch

# 从 builder 阶段直接把整个根文件系统拷贝过来
# 这一步操作会把之前几十层的所有变更，合并为一层
COPY --from=builder / /
# scratch ENV 需要固化的临时环境
# ENV 需要固化的临时环境
# 设置 miniforge PY_VERSION 版本，必须与第一阶段版本一致
ARG PY_VERSION=3.13.15
ARG CONDA_PY_ENV=py${PY_VERSION}
ARG CONDA_PROMPT_MODIFIER=(${CONDA_PY_ENV})
ARG CONDA_DEFAULT_ENV=${CONDA_PY_ENV}
ARG BUILD_HOME=/root
ARG MAMBA_ROOT_PREFIX=/opt/Miniforge
ARG _CONDA_ROOT=${MAMBA_ROOT_PREFIX}
# 某些 linux 系统可能需要导入 Miniforge 的 lib 环境
# 如果你需要这个，就执行，之后可能还需要手动写入到 bash 或 zsh 的配置文件中，以持续生效
# 但是我不确定是不是所有的 linux 都会 lib 缺失，先注释吧
#ARG LD_LIBRARY_PATH=${MAMBA_ROOT_PREFIX}/lib
ARG CONDA_PREFIX=${MAMBA_ROOT_PREFIX}/envs/${CONDA_PY_ENV}
ARG CONDA_EXE=${MAMBA_ROOT_PREFIX}/bin/conda
ARG _CONDA_EXE=${CONDA_EXE}
ARG CONDA_PYTHON_EXE=${MAMBA_ROOT_PREFIX}/bin/python
ARG JAVA_HOME=${BUILD_HOME}/.jbang/currentjdk
ARG CLASSPATH=.:${JAVA_HOME}/lib
# [新增] 定义 Go 工作目录，方便后续手动调试
ARG GOROOT="/opt/go"
ARG GOPATH="${BUILD_HOME}/go"
# [核心修改] 修改 PATH 定义
# 1. 优先加入 ${CONDA_PY_ENV}/bin：确保直接输入 python/jupyter 时调用的是主环境
# 2. 其次是 Miniforge/bin：确保能调用 conda/mamba
# 3. 再次是 Java/Jbang
# 4. 最后是系统原有的 PATH
ARG BUILD_PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
ARG PATH=${BUILD_PATH}:${MAMBA_ROOT_PREFIX}/envs/${CONDA_PY_ENV}/bin:${MAMBA_ROOT_PREFIX}/condabin:${MAMBA_ROOT_PREFIX}/bin:${BUILD_HOME}/.jbang/bin:${JAVA_HOME}/bin:${GOROOT}/bin:${GOPATH}/bin
ARG TERM=xterm

# 固化运行环境变量，全局构建和容器运行都可用，字符支持，安装目录，以及启动路径
# init_system.sh 所需固化环境 LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 LANGUAGE=zh_CN.UTF-8 LC_CTYPE=zh_CN.UTF-8
# install_miniforge.sh install_jupyter.sh clean.sh 所需固化环境 MAMBA_ROOT_PREFIX=/opt/Miniforge PATH=${MAMBA_ROOT_PREFIX}/bin:${PATH}
# install_jbang.sh 所需固化环境 PATH=$HOME/.jbang/bin:${PATH}
# install_jdk.sh 所需固化环境 JAVA_HOME=$HOME/.jbang/currentjdk CLASSPATH=.:$JAVA_HOME/lib PATH=$PATH:$JAVA_HOME/bin
# start_jupyter.sh 所需全部固化环境
# 某些 linux 系统可能需要导入 Miniforge 的 lib 环境
# 如果你需要这个，就执行，之后可能还需要手动写入到 bash 或 zsh 的配置文件中，以持续生效
# 但是我不确定是不是所有的 linux 都会 lib 缺失，先注释吧
# LD_LIBRARY_PATH=${LD_LIBRARY_PATH}
ENV LS_COLORS='rs=0:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:mi=00:su=37;41:sg=30;43:ca=00:tw=30;42:ow=34;42:st=37;44:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arc=01;31:*.arj=01;31:*.taz=01;31:*.lha=01;31:*.lz4=01;31:*.lzh=01;31:*.lzma=01;31:*.tlz=01;31:*.txz=01;31:*.tzo=01;31:*.t7z=01;31:*.zip=01;31:*.z=01;31:*.dz=01;31:*.gz=01;31:*.lrz=01;31:*.lz=01;31:*.lzo=01;31:*.xz=01;31:*.zst=01;31:*.tzst=01;31:*.bz2=01;31:*.bz=01;31:*.tbz=01;31:*.tbz2=01;31:*.tz=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.war=01;31:*.ear=01;31:*.sar=01;31:*.rar=01;31:*.alz=01;31:*.ace=01;31:*.zoo=01;31:*.cpio=01;31:*.7z=01;31:*.rz=01;31:*.cab=01;31:*.wim=01;31:*.swm=01;31:*.dwm=01;31:*.esd=01;31:*.avif=01;35:*.jpg=01;35:*.jpeg=01;35:*.mjpg=01;35:*.mjpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.svg=01;35:*.svgz=01;35:*.mng=01;35:*.pcx=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.m2v=01;35:*.mkv=01;35:*.webm=01;35:*.webp=01;35:*.ogm=01;35:*.mp4=01;35:*.m4v=01;35:*.mp4v=01;35:*.vob=01;35:*.qt=01;35:*.nuv=01;35:*.wmv=01;35:*.asf=01;35:*.rm=01;35:*.rmvb=01;35:*.flc=01;35:*.avi=01;35:*.fli=01;35:*.flv=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.yuv=01;35:*.cgm=01;35:*.emf=01;35:*.ogv=01;35:*.ogx=01;35:*.aac=00;36:*.au=00;36:*.flac=00;36:*.m4a=00;36:*.mid=00;36:*.midi=00;36:*.mka=00;36:*.mp3=00;36:*.mpc=00;36:*.ogg=00;36:*.ra=00;36:*.wav=00;36:*.oga=00;36:*.opus=00;36:*.spx=00;36:*.xspf=00;36:*~=00;90:*#=00;90:*.bak=00;90:*.old=00;90:*.orig=00;90:*.part=00;90:*.rej=00;90:*.swp=00;90:*.tmp=00;90:*.dpkg-dist=00;90:*.dpkg-old=00;90:*.ucf-dist=00;90:*.ucf-new=00;90:*.ucf-old=00;90:*.rpmnew=00;90:*.rpmorig=00;90:*.rpmsave=00;90:' \
    TERM=${TERM} \
    HOME=${BUILD_HOME} \
    SHELL=/bin/bash \
    LANG=zh_CN.UTF-8 \
    LC_ALL=zh_CN.UTF-8 \
    LANGUAGE=zh_CN.UTF-8 \
    LC_CTYPE=zh_CN.UTF-8 \
    CONDA_PY_ENV=${CONDA_PY_ENV} \
    CONDA_PROMPT_MODIFIER=${CONDA_PROMPT_MODIFIER} \
    MAMBA_ROOT_PREFIX=${MAMBA_ROOT_PREFIX} \
    _CONDA_ROOT=${_CONDA_ROOT} \
    CONDA_PREFIX=${CONDA_PREFIX} \
    CONDA_EXE=${CONDA_EXE} \
    _CONDA_EXE=${_CONDA_EXE} \
    CONDA_DEFAULT_ENV=${CONDA_DEFAULT_ENV} \
    CONDA_PYTHON_EXE=${CONDA_PYTHON_EXE} \
    JAVA_HOME=${JAVA_HOME} \
    CLASSPATH=${CLASSPATH} \
    GOROOT=${GOROOT} \
    # [新增] 固化 GOPATH
    GOPATH=${GOPATH} \
    # [关键] 固化修复后的 PATH
    PATH=${PATH}

# 添加常用LABEL（根据需要修改）添加标题 版本 作者 代码仓库 镜像说明，方便优化
LABEL org.opencontainers.image.description="miniforge 安装 jupyter notebook 封装特殊需求自用 python 测试容器." \
      org.opencontainers.image.title="Miniforge Jupyter" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.authors="yHUJibXnPx <bXnPxyHUJi@outlook.com>" \
      org.opencontainers.image.source="https://github.com/yHUJibXnPx/docker-arch-miniforge-jupyter" \
      org.opencontainers.image.licenses="MIT"

# 设置工作目录 /notebook 仅用于 Notebook 数据挂载（保持干净）
WORKDIR /notebook

# 固化端口
EXPOSE 8888
# 健康检查
HEALTHCHECK CMD curl -f http://localhost:8888 || exit 1

# 使用 tini 作为入口，调用 entrypoint 脚本或者直接启动 /usr/local/bin/start_jupyter.sh
ENTRYPOINT ["tini", "--"]
# 脚本执行
CMD [ "/usr/local/bin/start_jupyter.sh" ]
