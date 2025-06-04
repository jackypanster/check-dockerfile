# Dockerfile 镜像大小优化检查工具

这是一个专门用于检查 Dockerfile 和 .dockerignore 文件的脚本，旨在帮助减少 Docker 镜像大小，提高构建效率和安全性。该脚本特别适用于 Jenkins CI/CD 流水线。

## 🎯 主要功能

- ✅ **基础镜像优化检查** - 推荐使用轻量级镜像（alpine、slim）
- ✅ **包管理器优化** - 检查缓存清理和 `--no-install-recommends` 使用
- ✅ **多阶段构建检测** - 推荐分离构建和运行环境
- ✅ **层数优化** - 检查 RUN 指令合并机会
- ✅ **文件复制优化** - 避免不必要的文件进入镜像
- ✅ **.dockerignore 完整性** - 确保排除非必要文件
- ✅ **临时文件清理** - 检查缓存和临时文件清理
- ✅ **安全最佳实践** - 非 root 用户运行检查

## 📋 检查项目详情

### 1. .dockerignore 文件检查
- 文件存在性检查
- **防欺骗检查**: 检测空文件或只包含注释的无效文件
- **有效性验证**: 确保至少包含最少数量的实际忽略规则
- **关键项缺失检测**: 特别检查 .git、node_modules 等关键忽略项
- 常见忽略项检查（测试文件、文档、临时文件等）
- 影响镜像大小的重要文件检测

### 2. 基础镜像优化
- 检测是否使用轻量级变体（alpine、slim、scratch）
- 避免使用 `latest` 标签
- 推荐更小的基础镜像选择

### 3. 包管理器最佳实践
- **apt-get**: 检查 `--no-install-recommends`、缓存清理、指令合并
- **yum/dnf**: 检查 `clean all` 清理
- **apk**: 检查 `--no-cache` 选项和虚拟包使用

### 4. 构建优化
- 多阶段构建检测和推荐
- RUN 指令层数优化
- WORKDIR 使用检查

### 5. 文件管理
- 避免 `COPY .` 复制整个上下文
- 检测不必要文件复制（文档、测试等）
- ADD vs COPY 使用建议

### 6. 安全和最佳实践
- 非 root 用户运行检查
- 健康检查建议
- 端口暴露检查

## 🚀 使用方法

### 基本使用

```bash
# 检查当前目录的 Dockerfile
./check_dockerfile.sh

# 检查指定路径的 Dockerfile
./check_dockerfile.sh path/to/your/Dockerfile
```

### Jenkins Pipeline 集成

在 `Jenkinsfile` 中添加：

```groovy
pipeline {
    agent any
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Dockerfile Lint') {
            steps {
                script {
                    // 确保脚本有执行权限
                    sh 'chmod +x ./check_dockerfile.sh'
                    
                    // 执行检查，捕获退出码
                    def exitCode = sh(
                        script: './check_dockerfile.sh', 
                        returnStatus: true
                    )
                    
                    // 根据退出码设置构建状态
                    if (exitCode == 0) {
                        echo "✅ Dockerfile 检查通过"
                    } else if (exitCode == 1) {
                        currentBuild.result = 'FAILURE'
                        error("❌ Dockerfile 检查失败，存在错误")
                    } else if (exitCode == 2) {
                        currentBuild.result = 'UNSTABLE'
                        echo "⚠️ Dockerfile 检查发现警告，建议优化"
                    }
                }
            }
        }
        
        stage('Build Docker Image') {
            when {
                expression { 
                    currentBuild.result == null || 
                    currentBuild.result == 'SUCCESS' || 
                    currentBuild.result == 'UNSTABLE' 
                }
            }
            steps {
                sh 'docker build -t myapp:${BUILD_NUMBER} .'
            }
        }
    }
}
```

### GitHub Actions 集成

```yaml
name: Docker Build and Check

on: [push, pull_request]

jobs:
  dockerfile-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Make script executable
        run: chmod +x ./check_dockerfile.sh
      
      - name: Run Dockerfile checks
        run: ./check_dockerfile.sh
        
      - name: Build Docker image
        if: success()
        run: docker build -t myapp:latest .
```

## 📊 退出码说明

| 退出码 | 含义 | Jenkins 建议状态 | 触发条件示例 |
|--------|------|------------------|-------------|
| 0 | 检查完全通过 | SUCCESS | 所有检查都通过，无错误无警告 |
| 1 | 检测到错误 | FAILURE | 空 .dockerignore、USER root、基础镜像使用 latest 等 |
| 2 | 仅有警告 | UNSTABLE | 未使用多阶段构建、包管理器缓存未清理等 |

## 🔒 安全特性

### 防止 .dockerignore 绕过检查

脚本包含多层验证，防止用户通过提交无效的 .dockerignore 文件来绕过检查：

1. **空文件检测** - 直接报错，退出码为 1
2. **纯注释文件检测** - 检测只包含注释和空行的文件，报错
3. **最小规则数量检查** - 要求至少 3 条有效规则，否则警告
4. **关键项缺失检测** - 特别检查 .git、node_modules 等关键忽略项

```bash
# ❌ 这些会被检测为错误：
echo "" > .dockerignore                    # 空文件
echo "# only comments" > .dockerignore     # 只有注释

# ⚠️ 这个会产生警告：
echo -e ".git\n*.log" > .dockerignore      # 规则太少（<3条）

# ✅ 这个会通过检查：
cp .dockerignore.example .dockerignore     # 完整的忽略规则
```

## 🛠️ 自定义配置

### 修改检查规则
您可以根据项目需求修改脚本中的检查规则：

```bash
# 修改常见忽略项列表
common_ignores=(
    ".git" "node_modules" "target/" "dist/" "build/" 
    "*.log" ".env" "coverage/" ".pytest_cache/" 
    "__pycache__/" # 添加或删除项目
)

# 调整 RUN 指令数量阈值
if [ "$run_count" -gt 5 ]; then  # 修改这里的数字
```

### 警告作为错误处理
如果希望警告也导致构建失败，修改退出逻辑：

```bash
elif [ "${WARNING_COUNT}" -gt 0 ]; then
    echo "${YELLOW}⚠️  状态: 检查发现警告${RESET}"
    exit_code=1  # 改为 1 使警告也导致失败
```

## 💡 镜像大小优化建议

### 基础镜像选择
```dockerfile
# ❌ 避免使用大型镜像
FROM ubuntu:latest

# ✅ 推荐使用轻量级镜像
FROM node:18-alpine
FROM python:3.11-slim
FROM golang:1.21-alpine
```

### 多阶段构建示例
```dockerfile
# 构建阶段
FROM node:18-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

# 运行阶段
FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
```

### 包管理器优化
```dockerfile
# ✅ 推荐的 apt-get 用法
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ✅ 推荐的 apk 用法
RUN apk add --no-cache --virtual .build-deps \
        gcc \
        musl-dev \
    && apk add --no-cache \
        python3 \
        py3-pip \
    && pip install requirements.txt \
    && apk del .build-deps
```

### .dockerignore 示例
```
# 版本控制
.git
.gitignore

# 文档
README.md
docs/
*.md

# 测试和开发
test/
tests/
spec/
coverage/
.nyc_output

# 依赖和构建产物
node_modules/
target/
dist/
build/

# 日志和临时文件
*.log
*.tmp
.cache/

# IDE 和编辑器
.vscode/
.idea/
*.swp
*.swo

# 环境变量和配置
.env*
.DS_Store

# Docker 相关
Dockerfile*
.dockerignore
docker-compose*
```

## 🔍 示例输出

```
======================================================
🐳 Dockerfile 镜像大小优化检查开始 (用于 Jenkins CI)
目标 Dockerfile: Dockerfile
目标 .dockerignore: .dockerignore
======================================================

--- 📄 检查 .dockerignore 文件 ---
✅ 通过: .dockerignore 文件存在。
✅ 通过: .dockerignore 文件包含了重要的排除模式。

--- 🐳 Dockerfile 内容检查 ---

[检查1]: 基础镜像优化检查
✅ 通过: 检测到使用了轻量级基础镜像 (alpine/slim/scratch)。

[检查2]: WORKDIR 指令检查
✅ 通过: 检测到 WORKDIR 指令。

[检查3]: 包管理器缓存清理检查
✅ 通过: 包管理器缓存清理检查通过。

...

======================================================
🐳 Dockerfile 镜像大小优化检查完成
发现 0 个错误, 0 个警告
✅ 状态: 检查完全通过，Dockerfile 已遵循镜像大小优化最佳实践
======================================================
```

## 📈 最佳实践总结

1. **使用轻量级基础镜像** - alpine、slim 变体可减少 60-80% 镜像大小
2. **多阶段构建** - 分离构建和运行环境，只保留运行时必需文件
3. **合并 RUN 指令** - 减少镜像层数，降低存储开销
4. **清理包管理器缓存** - 避免在镜像中保留下载缓存
5. **使用 .dockerignore** - 排除不必要文件，减小构建上下文
6. **及时清理临时文件** - 删除构建过程中的临时文件和缓存

## 🤝 贡献

欢迎提交 Issue 和 Pull Request 来改进这个工具！

## �� 许可证

MIT License 