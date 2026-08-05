# SaaS Hub 服务镜像
# 构建上下文必须在仓库根目录（saas-hub 依赖上层 src/shared/）
# 构建：docker build -t ztoken-monitor-saas-hub -f saas-hub/Dockerfile .
# 运行：见 saas-hub/DOCKER.md

FROM node:22-alpine

# 时区（影响日志和 received_at 等时间戳显示）
RUN apk add --no-cache tzdata && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone

WORKDIR /app

# 先拷贝依赖清单，利用层缓存
COPY saas-hub/package.json saas-hub/package-lock.json* ./saas-hub/

# saas-hub 依赖 src/shared（纯函数，运行时 require），一并拷入
COPY src/shared ./src/shared

WORKDIR /app/saas-hub

# 只装 saas-hub 的依赖（生产依赖，不装 devDependencies）
RUN npm install --omit=dev --no-audit --no-fund

# 拷贝 saas-hub 源码
COPY saas-hub ./

EXPOSE 8787

# 入口：直接跑 server.js
CMD ["node", "src/server.js"]
