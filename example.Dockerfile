# 这是一个示例 Dockerfile，包含一些可以优化的地方
FROM node:18

# 没有设置 WORKDIR
RUN mkdir /app
RUN cd /app

# 复制整个上下文（可能包含不必要的文件）
COPY . .

# 分开的 RUN 指令，可以合并
RUN apt-get update
RUN apt-get install -y curl git
RUN npm install

# 未清理包管理器缓存
RUN apt-get install -y vim

# 暴露端口
EXPOSE 3000

# 以 root 用户运行（安全问题）
CMD ["npm", "start"] 