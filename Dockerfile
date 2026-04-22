# ==============================================================================
# 阶段 1: builder - 构建一个包含所有基础依赖的稳定环境
# ==============================================================================
FROM node:24-slim AS builder

# 从 Python 官方镜像拷贝 Python 3.12
COPY --from=python:3.12-slim-bookworm /usr/local /usr/local

WORKDIR /app

ENV BUN_INSTALL="/usr/local" \
    PATH="/usr/local/bin:$PATH" \
    DEBIAN_FRONTEND=noninteractive

# -- 核心步骤：安装所有不常变化的系统依赖和最新的全局工具 --
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    bash ca-certificates chromium curl docker.io build-essential ffmpeg \
    fonts-liberation fonts-noto-cjk fonts-noto-color-emoji git gosu jq vim nano\
    locales openssh-client procps socat tini iputils-ping dnsutils unzip && \
    sed -i 's/^# *en_US.UTF-8 UTF-8$/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen && \
    printf 'LANG=en_US.UTF-8\nLANGUAGE=en_US:en\nLC_ALL=en_US.UTF-8\n' > /etc/default/locale && \
    git config --system url."https://github.com/".insteadOf ssh://git@github.com/ && \
    npm config set registry https://registry.npmmirror.com && \
    npm install -g \
        opencode-ai \
        clawhub \
        playwright \
        playwright-extra \
        puppeteer-extra-plugin-stealth \
        @steipete/bird \
        agent-browser \
        @tobilu/qmd && \
    curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash && \
    curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh && \
    ln -sf /usr/local/bin/python3 /usr/local/bin/python && \
    python3 -m pip install --no-cache-dir websockify && \
    npx playwright install chromium --with-deps && \
    apt-get purge -y --auto-remove && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# -- 为 node 用户安装 Homebrew --
RUN mkdir -p /home/node && chown -R node:node /home/node
USER node
WORKDIR /home/node
ENV HOME=/home/node
RUN mkdir -p .linuxbrew/Homebrew && \
    git clone --depth 1 https://github.com/Homebrew/brew .linuxbrew/Homebrew && \
    mkdir -p .linuxbrew/bin && \
    ln -s /home/node/.linuxbrew/Homebrew/bin/brew /home/node/.linuxbrew/bin/brew && \
    chmod -R g+rwX .linuxbrew

# ==============================================================================
# 阶段 2: final - 构建最终的、轻量的生产镜像
# ==============================================================================
FROM node:24-slim

ARG NAPCAT_VERSION=v4.17.25
ARG APP_VERSION=2026.4.20
ARG CLAWHUB_TOKEN

# -- 从 builder 阶段拷贝所有预装好的环境和工具 --
COPY --from=builder /usr/local /usr/local
COPY --from=builder /etc/locale.gen /etc/locale.gen
COPY --from=builder /etc/default/locale /etc/default/locale
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /usr/share/fonts /usr/share/fonts
COPY --from=builder /var/lib/dpkg /var/lib/dpkg
COPY --from=builder /var/lib/apt/extended_states /var/lib/apt/extended_states
COPY --from=builder /usr/bin/chromium /usr/bin/chromium
COPY --from=builder --chown=node:node /home/node /home/node

# 设置环境变量
ENV BUN_INSTALL="/usr/local" \
    DEBIAN_FRONTEND=noninteractive \
    HOME=/home/node \
    TERM=xterm-256color \
    NODE_PATH=/usr/local/lib/node_modules \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    NODE_ENV=production \
    PATH="/home/node/.linuxbrew/bin:/home/node/.linuxbrew/sbin:/usr/local/lib/node_modules/.bin:/usr/local/bin:$PATH" \
    HOMEBREW_NO_AUTO_UPDATE=1 \
    AGENT_BROWSER_CHROME_PATH=/usr/bin/chromium \
    HOMEBREW_NO_INSTALL_CLEANUP=1

# --- 釜底抽薪的最终修正 ---
# 切换到 node 用户 ，然后在一个 RUN 指令中完成所有相关操作
USER node
WORKDIR /home/node
RUN \
    # 步骤 1: 作为 node 用户，安装 openclaw
    npm config set registry https://registry.npmmirror.com && \
    npm install -g openclaw@${APP_VERSION} && \
    \
    # 步骤 2: 立即开始安装插件 ，此时环境绝对一致
    mkdir -p /home/node/.openclaw/workspace && \
    if [ -n "$CLAWHUB_TOKEN" ]; then clawhub login --token "$CLAWHUB_TOKEN"; fi && \
    cd /home/node/.openclaw && \
    mkdir extensions && cd extensions && \
    git clone --depth 1 -b "${NAPCAT_VERSION}" https://github.com/Daiyimo/openclaw-napcat.git napcat && \
    cd napcat && npm install --production && cd .. && \
    timeout 300 openclaw plugins install --dangerously-force-unsafe-install -l ./napcat || true && \
    timeout 300 openclaw plugins install --dangerously-force-unsafe-install @soimy/dingtalk || true && \
    timeout 300 openclaw plugins install --dangerously-force-unsafe-install @tencent-connect/openclaw-qqbot || true && \
    timeout 300 openclaw plugins install --dangerously-force-unsafe-install @sunnoy/wecom || true && \
    \
    # 步骤 3: 创建种子目录并清理
    cd /home/node && \
    mkdir -p .openclaw-seed && \
    mv .openclaw/extensions .openclaw-seed/ && \
    find .openclaw-seed/extensions -name ".git" -type d -exec rm -rf {} + && \
    printf '%s\n' "${APP_VERSION}" > .openclaw-seed/extensions/.seed-version && \
    rm -rf /tmp/* .npm .cache

# -- 最终配置和入口点 --
USER root
COPY ./init.sh /usr/local/bin/init.sh
RUN sed -i 's/\r$//' /usr/local/bin/init.sh && chmod +x /usr/local/bin/init.sh

EXPOSE 18789
WORKDIR /home/node
ENTRYPOINT ["/bin/bash", "/usr/local/bin/init.sh"]
