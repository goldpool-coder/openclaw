# ==============================================================================
# 返璞归真：单阶段、单用户、分步执行的“笨办法”构建
# 目标：100% 构建成功，即使牺牲速度和镜像大小
# ==============================================================================
FROM node:24-slim

# --- 1. 定义所有构建参数 ---
ARG NAPCAT_VERSION=v4.17.25
ARG APP_VERSION=2026.4.20
ARG CLAWHUB_TOKEN

# --- 2. 拷贝 Python 并设置基础环境 (全部以 root 用户执行) ---
COPY --from=python:3.12-slim-bookworm /usr/local /usr/local
WORKDIR /app
ENV BUN_INSTALL="/usr/local" \
    PATH="/usr/local/bin:$PATH" \
    DEBIAN_FRONTEND=noninteractive

# --- 3. 耗时最长的步骤：安装系统依赖和基础工具 (第一层缓存) ---
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    bash ca-certificates chromium curl docker.io build-essential ffmpeg \
    fonts-liberation fonts-noto-cjk fonts-noto-color-emoji git gosu jq vim nano\
    locales openssh-client procps socat tini iputils-ping dnsutils unzip && \
    sed -i 's/^# *en_US.UTF-8 UTF-8$/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen && \
    printf 'LANG=en_US.UTF-8\nLANGUAGE=en_US:en\nLC_ALL=en_US.UTF-8\n' > /etc/default/locale && \
    git config --system url."https://github.com/".insteadOf ssh://git@github.com/ && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# --- 4. 安装全局 NPM 包和 Python 工具 (第二层缓存 ) ---
RUN npm config set registry https://registry.npmmirror.com && \
    npm install -g \
        opencode-ai \
        clawhub \
        playwright \
        playwright-extra \
        puppeteer-extra-plugin-stealth \
        @steipete/bird \
        agent-browser \
        @tobilu/qmd \
        openclaw@${APP_VERSION} && \
    curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash && \
    curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh && \
    ln -sf /usr/local/bin/python3 /usr/local/bin/python && \
    python3 -m pip install --no-cache-dir websockify && \
    npx playwright install chromium --with-deps && \
    rm -rf /tmp/* /root/.npm /root/.cache

# --- 5. 安装 Homebrew (第三层缓存 ) ---
# 我们将 Homebrew 安装到 /home/linuxbrew，并让 root 拥有它
RUN mkdir -p /home/linuxbrew && chown -R root:root /home/linuxbrew
WORKDIR /home/linuxbrew
RUN git clone --depth 1 https://github.com/Homebrew/brew .
ENV PATH="/home/linuxbrew/bin:${PATH}"

# --- 6. 安装插件 (最容易出错的步骤 ，单独一层) ---
WORKDIR /app # 回到主工作目录
RUN mkdir -p /root/.openclaw/workspace && \
    if [ -n "$CLAWHUB_TOKEN" ]; then clawhub login --token "$CLAWHUB_TOKEN"; fi && \
    cd /root/.openclaw && \
    mkdir extensions && cd extensions && \
    git clone --depth 1 -b "${NAPCAT_VERSION}" https://github.com/Daiyimo/openclaw-napcat.git napcat && \
    cd napcat && npm install --production && cd .. && \
    timeout 300 openclaw plugins install --dangerously-force-unsafe-install -l ./napcat || true && \
    timeout 300 openclaw plugins install --dangerously-force-unsafe-install @soimy/dingtalk || true && \
    timeout 300 openclaw plugins install --dangerously-force-unsafe-install @tencent-connect/openclaw-qqbot || true && \
    timeout 300 openclaw plugins install --dangerously-force-unsafe-install @sunnoy/wecom || true

# --- 7. 创建种子目录并清理 ---
RUN mkdir -p /root/.openclaw-seed && \
    mv /root/.openclaw/extensions /root/.openclaw-seed/ && \
    find /root/.openclaw-seed/extensions -name ".git" -type d -exec rm -rf {} + && \
    printf '%s\n' "${APP_VERSION}" > /root/.openclaw-seed/extensions/.seed-version && \
    rm -rf /tmp/* /root/.npm /root/.cache

# --- 8. 最终配置和入口点 ---
COPY ./init.sh /usr/local/bin/init.sh
RUN sed -i 's/\r$//' /usr/local/bin/init.sh && chmod +x /usr/local/bin/init.sh

# 最终的环境变量
ENV HOME=/root \
    TERM=xterm-256color \
    NODE_PATH=/usr/local/lib/node_modules \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    NODE_ENV=production \
    PATH="/home/linuxbrew/bin:/home/linuxbrew/sbin:/usr/local/lib/node_modules/.bin:${PATH}" \
    HOMEBREW_NO_AUTO_UPDATE=1 \
    AGENT_BROWSER_CHROME_PATH=/usr/bin/chromium \
    HOMEBREW_NO_INSTALL_CLEANUP=1

EXPOSE 18789
WORKDIR /app
ENTRYPOINT ["/bin/bash", "/usr/local/bin/init.sh"]
