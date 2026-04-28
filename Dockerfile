# OpenClaw Docker 镜像 

# --- 1. 定义所有构建时参数 ---
ARG APP_VERSION=2026.4.26
ARG NAPCAT_VERSION=v4.17.25

# 基础镜像
FROM node:24-slim

# 从 Python 官方镜像拷贝 Python 3.12
COPY --from=python:3.12-slim-bookworm /usr/local /usr/local

# 设置工作目录
WORKDIR /app

# 设置环境变量
ENV BUN_INSTALL="/usr/local" \
    PATH="/usr/local/bin:$PATH" \
    NODE_LLAMA_CPP_GPU=false \
    DEBIAN_FRONTEND=noninteractive

# --- 2. 安装【除 openclaw 外】的所有系统依赖和全局工具 (稳定的基础层) ---
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    bash ca-certificates chromium curl docker.io build-essential ffmpeg \
    fonts-liberation fonts-noto-cjk fonts-noto-color-emoji git gosu jq vim nano \
    locales openssh-client procps socat tini unzip && \
    sed -i 's/^# *en_US.UTF-8 UTF-8$/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen && \
    printf 'LANG=en_US.UTF-8\nLANGUAGE=en_US:en\nLC_ALL=en_US.UTF-8\n' > /etc/default/locale && \
    git config --system url."https://github.com/".insteadOf ssh://git@github.com/ && \
    npm config set registry https://registry.npmmirror.com && \
    npm install -g opencode-ai@latest clawhub playwright playwright-extra puppeteer-extra-plugin-stealth @steipete/bird @larksuiteoapi/node-sdk @tobilu/qmd && \
    curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash && \
    curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh && \
    ln -sf /usr/local/bin/python3 /usr/local/bin/python && \
    /usr/local/bin/python3 -m pip install --no-cache-dir websockify && \
    npx playwright install chromium --with-deps && \
    apt-get purge -y --auto-remove && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /root/.npm /root/.cache

# --- 3. 【只】安装 openclaw (频繁变动的应用层，用于缓存优化) ---
ARG APP_VERSION
RUN npm config set registry https://registry.npmmirror.com && \
    npm install -g openclaw@${APP_VERSION} && \
    rm -rf /tmp/* /root/.npm /root/.cache

# --- 4. 准备 node 用户环境并安装插件 ---
RUN mkdir -p /home/node/.openclaw/workspace /home/node/.openclaw/extensions && \
    mkdir -p /var/tmp/openclaw-compile-cache /tmp/openclaw-1000 /home/node/.cache/qmd && \
    chown -R node:node /usr/local/lib/node_modules /home/node/.cache/qmd && \
    chown -R node:node /home/node /var/tmp/openclaw-compile-cache /var/tmp/openclaw-compile-cache /tmp/openclaw-1000 && \
    chmod 700 /tmp/openclaw-1000
    
USER node
ENV HOME=/home/node \
    PATH="/home/node/.linuxbrew/bin:/home/node/.linuxbrew/Homebrew/bin:${PATH}"

WORKDIR /home/node

# 安装 linuxbrew
RUN mkdir -p /home/node/.linuxbrew/Homebrew && \
    git clone --depth 1 https://github.com/Homebrew/brew /home/node/.linuxbrew/Homebrew && \
    mkdir -p /home/node/.linuxbrew/bin && \
    ln -s /home/node/.linuxbrew/Homebrew/bin/brew /home/node/.linuxbrew/bin/brew && \
    chown -R node:node /home/node/.linuxbrew && \
    chmod -R g+rwX /home/node/.linuxbrew && \
    # 安装 gog, 将 brew install gogcli 改为了 brew install steipete/tap/gogcli，否则安装的可能是另一个 homebrew/core/gogcli 了
    brew install steipete/tap/gogcli

# 再次声明 ARG ，以便在 node 用户的 RUN 指令中使用
ARG APP_VERSION
ARG NAPCAT_VERSION
ARG CLAWHUB_TOKEN
RUN if [ -n "$CLAWHUB_TOKEN" ]; then clawhub login --token "$CLAWHUB_TOKEN"; fi && \
  cd /home/node/.openclaw/extensions && \
  git clone --depth 1 -b "${NAPCAT_VERSION}" https://github.com/Daiyimo/openclaw-napcat.git napcat && \
  cd napcat && \
  npm install --production && \
  timeout 300 openclaw plugins install --dangerously-force-unsafe-install -l . || true && \
  cd /home/node/.openclaw/extensions && \
  timeout 300 openclaw plugins install --dangerously-force-unsafe-install @soimy/dingtalk || true && \
  timeout 300 openclaw plugins install --dangerously-force-unsafe-install @tencent-connect/openclaw-qqbot@latest || true && \
  timeout 300 openclaw plugins install --dangerously-force-unsafe-install @sunnoy/wecom || true && \
  mkdir -p /home/node/.openclaw /home/node/.openclaw-seed && \
  find /home/node/.openclaw/extensions -name ".git" -type d -exec rm -rf {} + && \
  mv /home/node/.openclaw/extensions /home/node/.openclaw-seed/ && \
  printf '%s\n' "${APP_VERSION}" > /home/node/.openclaw-seed/extensions/.seed-version && \
  rm -rf /tmp/* /home/node/.npm /home/node/.cache
  
# --- 5. 最终配置 ---
USER root
COPY ./init.sh /usr/local/bin/init.sh
RUN sed -i 's/\r$//' /usr/local/bin/init.sh && \
    chmod +x /usr/local/bin/init.sh

# 设置最终的环境变量
ENV HOME=/home/node \
    TERM=xterm-256color \
    NODE_PATH=/usr/local/lib/node_modules \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    NODE_ENV=production \
    PATH="/home/node/.linuxbrew/bin:/home/node/.linuxbrew/sbin:/usr/local/lib/node_modules/.bin:${PATH}" \
    AGENT_BROWSER_CHROME_PATH=/usr/bin/chromium \
    NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache \
    OPENCLAW_NO_RESPAWN=1 \
    QMD_LLAMA_GPU=false \
    NODE_LLAMA_CPP_GPU=false \
    HOMEBREW_NO_AUTO_UPDATE=1 \
    HOMEBREW_NO_INSTALL_CLEANUP=1

# 暴露端口
EXPOSE 18789

# 设置最终工作目录
WORKDIR /home/node

# 设置入口点
ENTRYPOINT ["/bin/bash", "/usr/local/bin/init.sh"]
