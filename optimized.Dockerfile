# 优化后的 Dockerfile，遵循镜像大小优化最佳实践

# 使用轻量级基础镜像，并指定具体版本
FROM node:18-alpine

# 添加标签信息
LABEL maintainer="yourteam@example.com"
LABEL version="1.0.0"
LABEL description="Optimized Node.js application"

# 设置工作目录
WORKDIR /app

# 创建非 root 用户
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nextjs -u 1001

# 先复制 package 文件，利用 Docker 缓存
COPY package*.json ./

# 安装依赖，使用单个 RUN 指令合并操作
RUN apk add --no-cache --virtual .build-deps \
        python3 \
        make \
        g++ && \
    npm ci --only=production && \
    npm cache clean --force && \
    apk del .build-deps && \
    rm -rf /tmp/* /var/tmp/* ~/.npm

# 复制应用代码（使用 .dockerignore 排除不必要文件）
COPY --chown=nextjs:nodejs src/ ./src/
COPY --chown=nextjs:nodejs public/ ./public/

# 切换到非 root 用户
USER nextjs

# 暴露端口
EXPOSE 3000

# 添加健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# 启动应用
CMD ["npm", "start"] 