# -----------------------------------------------------------------
# Dockerfile for your new project (e.g., openclaw-plus)
# -----------------------------------------------------------------

# 1. 继承父项目的最终镜像
# 这一步会直接利用父镜像的所有层，包括所有已安装的依赖和配置。
# 构建时，Docker会先拉取这个镜像（如果本地没有的话）。
FROM justlikemaki/openclaw-docker-cn-im:latest

# 2. 切换到 root 用户以获取安装权限
# 父镜像的最后一条指令可能是 USER node，我们需要切换回 root 来执行 apt-get。
USER root

# 3. 安装 ping 命令并清理缓存
# 这是你唯一需要新增的构建步骤。
# 使用 --no-install-recommends 避免安装不必要的包。
# 安装后立即清理，保持镜像体积最优。
RUN apt-get update && \
    apt-get install -y --no-install-recommends iputils-ping dnsutils && \
    npm install -g npm@latest && \
    npm install -g clawhub && \
    rm -rf /var/lib/apt/lists/*

# 4. (可选) 切换回默认用户
# 如果你想让容器默认以非 root 用户运行，可以切换回去。
# 父镜像的默认用户是 node，这是一个好习惯。
USER node

ENV PATH="/home/node/.linuxbrew/bin:${PATH}"
RUN brew install gh && \
    brew cleanup --prune=all 

# 5. (可选) 重新声明工作目录
# 父镜像的 WORKDIR 是 /home/node，继承时也会保留。
# 如果你想让它更明确，可以重新声明一下。
WORKDIR /home/node

# 父镜像的 ENTRYPOINT 和 CMD 会被自动继承，所以你不需要重新写。
