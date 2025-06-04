#!/bin/bash

# 用于 Jenkins CI 的 Dockerfile 与 .dockerignore 基础检查脚本
# 专注于减少 Docker 镜像大小的最佳实践检查
#
# 使用方法:
# 1. 将此脚本保存到您的代码仓库中 (例如: scripts/check_dockerfile.sh)
# 2. 在 Jenkins Pipeline 中，检出代码后，执行此脚本:
#    sh './scripts/check_dockerfile.sh path/to/your/Dockerfile'
#    或者，如果 Dockerfile 在根目录:
#    sh './scripts/check_dockerfile.sh'
# 3. 脚本会根据检查结果返回退出码：
#    0: 通过检查 (或仅有信息性提示)
#    1: 检测到错误
#    2: 检测到警告但无错误

DOCKERFILE_PATH="${1:-Dockerfile}" # 默认检查项目根目录下的 Dockerfile
DOCKERIGNORE_PATH=".dockerignore" # .dockerignore 文件应位于构建上下文的根目录

# 错误和警告计数器
ERROR_COUNT=0
WARNING_COUNT=0

# 辅助函数，用于打印带颜色的消息
if command -v tput > /dev/null && tty -s; then
    RED=$(tput setaf 1)
    YELLOW=$(tput setaf 3)
    GREEN=$(tput setaf 2)
    BLUE=$(tput setaf 4)
    CYAN=$(tput setaf 6)
    RESET=$(tput sgr0)
else
    RED=""
    YELLOW=""
    GREEN=""
    BLUE=""
    CYAN=""
    RESET=""
fi

log_error() {
    echo "${RED}❌ 错误: $1${RESET}"
    ERROR_COUNT=$((ERROR_COUNT + 1))
}

log_warning() {
    echo "${YELLOW}⚠️  警告: $1${RESET}"
    WARNING_COUNT=$((WARNING_COUNT + 1))
}

log_info() {
    echo "${BLUE}ℹ️  信息: $1${RESET}"
}

log_success() {
    echo "${GREEN}✅ 通过: $1${RESET}"
}

log_tip() {
    echo "${CYAN}💡 建议: $1${RESET}"
}

echo "======================================================"
echo "🐳 Dockerfile 镜像大小优化检查开始 (用于 Jenkins CI)"
echo "目标 Dockerfile: ${DOCKERFILE_PATH}"
echo "目标 .dockerignore: ${DOCKERIGNORE_PATH}"
echo "======================================================"

# 检查 Dockerfile 是否存在
if [ ! -f "${DOCKERFILE_PATH}" ]; then
    log_error "Dockerfile 文件 '${DOCKERFILE_PATH}' 未找到。"
    exit 1
fi

# --- 检查 .dockerignore 文件 ---
echo -e "\n--- 📄 检查 .dockerignore 文件 ---"
if [ ! -f "${DOCKERIGNORE_PATH}" ]; then
    log_warning "未找到 .dockerignore 文件。强烈建议添加 .dockerignore 文件以排除不必要的文件，这可以显著减小构建上下文、加快构建速度并增强安全性。"
    log_tip "创建 .dockerignore 文件示例内容："
    echo "    .git"
    echo "    .gitignore"
    echo "    README.md"
    echo "    Dockerfile*"
    echo "    .dockerignore"
    echo "    node_modules"
    echo "    npm-debug.log*"
    echo "    target/"
    echo "    dist/"
    echo "    *.log"
    echo "    .env*"
    echo "    coverage/"
    echo "    .pytest_cache/"
    echo "    __pycache__/"
else
    log_success ".dockerignore 文件存在。"
    
    # 检查文件是否为空或者只包含无效内容
    if [ ! -s "${DOCKERIGNORE_PATH}" ]; then
        log_error ".dockerignore 文件为空。空文件无法起到排除作用，这可能是试图绕过检查的行为。"
    else
        # 检查是否只包含注释和空行（有效性检查）
        effective_lines=$(grep -v -E '^\s*#|^\s*$' "${DOCKERIGNORE_PATH}" | wc -l)
        total_lines=$(wc -l < "${DOCKERIGNORE_PATH}")
        
        if [ "$effective_lines" -eq 0 ]; then
            log_error ".dockerignore 文件只包含注释和空行，没有实际的忽略规则。这无法起到排除文件的作用。"
        elif [ "$effective_lines" -lt 3 ]; then
            log_warning ".dockerignore 文件只有 ${effective_lines} 条有效规则，这可能不足以有效减小构建上下文。"
            log_tip "建议至少包含常见的忽略项如: .git, node_modules, *.log 等"
        else
            log_success ".dockerignore 文件包含 ${effective_lines} 条有效忽略规则。"
            
            # 扩展的常见忽略项检查，重点关注影响镜像大小的文件
            common_ignores=(
                ".git" "node_modules" "target/" "dist/" "build/" "*.log" ".env"
                "coverage/" ".pytest_cache/" "__pycache__/" ".DS_Store" "*.tmp"
                "*.swp" "*.swo" ".vscode/" ".idea/" "*.md" "docs/" "test/" "tests/"
                "spec/" "*.test.js" "*.spec.js" ".gitignore" "Dockerfile*" ".dockerignore"
            )
            missing_important_ignores=0
            missing_critical_ignores=0
            
            for item in "${common_ignores[@]}"; do
                if ! grep -q "${item}" "${DOCKERIGNORE_PATH}"; then
                    case "$item" in
                        ".git"|"node_modules"|"target/"|"__pycache__/"|"coverage/")
                            log_info "重要提示: .dockerignore 缺少 '${item}'，这可能显著增加镜像大小。"
                            missing_important_ignores=$((missing_important_ignores + 1))
                            if [ "$item" = ".git" ] || [ "$item" = "node_modules" ]; then
                                missing_critical_ignores=$((missing_critical_ignores + 1))
                            fi
                            ;;
                        "*.md"|"docs/"|"test/"|"tests/"|"spec/")
                            log_info "建议: .dockerignore 可添加 '${item}' 以排除文档和测试文件。"
                            ;;
                    esac
                fi
            done
            
            # 对于缺少关键忽略项的情况给出更严重的警告
            if [ "$missing_critical_ignores" -gt 0 ]; then
                log_warning "缺少关键的忽略项（.git、node_modules），这可能导致镜像体积显著增大。"
            elif [ "$missing_important_ignores" -eq 0 ]; then
                log_success ".dockerignore 文件包含了重要的排除模式。"
            else
                log_info "发现 ${missing_important_ignores} 个可优化的忽略项，建议添加以进一步减小镜像体积。"
            fi
        fi
    fi
fi

# --- Dockerfile 内容检查 ---
echo -e "\n--- 🐳 Dockerfile 内容检查 ---"

# 1. 检查基础镜像是否使用轻量级版本
echo -e "\n[检查1]: 基础镜像优化检查"
base_images=$(grep -E "^\s*FROM\s+" "${DOCKERFILE_PATH}" | head -1)
if echo "$base_images" | grep -q -E "(alpine|slim|scratch)"; then
    log_success "检测到使用了轻量级基础镜像 (alpine/slim/scratch)。"
elif echo "$base_images" | grep -q -E ":\s*latest\s*$"; then
    log_error "检测到基础镜像使用了 'latest' 标签且非轻量级版本。建议使用明确版本号和轻量级变体 (如 alpine)。"
else
    if echo "$base_images" | grep -q -E "(ubuntu|debian|centos|fedora)"; then
        log_warning "检测到使用了较大的基础镜像。考虑使用 alpine 或 slim 变体以减小镜像体积。"
        log_tip "例如: node:18-alpine 替代 node:18, python:3.11-slim 替代 python:3.11"
    else
        log_success "基础镜像检查通过。"
    fi
fi

# 2. 检查是否设置了 WORKDIR
echo -e "\n[检查2]: WORKDIR 指令检查"
if ! grep -q -E "^\s*WORKDIR\s+" "${DOCKERFILE_PATH}"; then
    log_warning "未检测到 WORKDIR 指令。建议使用 WORKDIR 而不是 'RUN cd' 来组织文件结构。"
else
    log_success "检测到 WORKDIR 指令。"
fi

# 3. 增强的包管理器缓存清理检查
echo -e "\n[检查3]: 包管理器缓存清理检查"
has_package_management=false

# 检查 apt-get
if grep -q "apt-get" "${DOCKERFILE_PATH}"; then
    has_package_management=true
    if grep -q "apt-get update" "${DOCKERFILE_PATH}"; then
        if ! grep -q -- "--no-install-recommends" "${DOCKERFILE_PATH}"; then
            log_warning "检测到 apt-get install 未使用 --no-install-recommends 选项，这会安装推荐包并增加镜像大小。"
        fi
        
        if ! grep -E "apt-get clean\s*&&\s*rm\s+-rf\s+/var/lib/apt/lists/\*" "${DOCKERFILE_PATH}" > /dev/null; then
            log_warning "检测到 apt-get 操作后未清理缓存。建议在同一 RUN 指令中添加: && apt-get clean && rm -rf /var/lib/apt/lists/*"
        fi
        
        # 检查是否合并了 update 和 install
        if ! grep -E "apt-get update\s*&&\s*apt-get install" "${DOCKERFILE_PATH}" > /dev/null; then
            log_warning "建议将 apt-get update 和 apt-get install 合并到同一 RUN 指令中。"
        fi
    fi
fi

# 检查 yum/dnf
if grep -q -E "(yum|dnf) install" "${DOCKERFILE_PATH}"; then
    has_package_management=true
    if ! grep -q -E "(yum|dnf) clean all" "${DOCKERFILE_PATH}"; then
        log_warning "检测到 yum/dnf 安装后未清理缓存。建议添加 && yum clean all"
    fi
fi

# 检查 apk
if grep -q "apk add" "${DOCKERFILE_PATH}"; then
    has_package_management=true
    if ! grep -q -- "--no-cache" "${DOCKERFILE_PATH}"; then
        if ! grep -q "apk del" "${DOCKERFILE_PATH}"; then
            log_warning "检测到 apk add 未使用 --no-cache 选项。建议使用 --no-cache 或在构建后删除临时依赖。"
        fi
    fi
    if ! grep -q -- "--virtual" "${DOCKERFILE_PATH}" && grep -q "apk add.*gcc\|make\|build" "${DOCKERFILE_PATH}"; then
        log_info "建议对构建依赖使用 --virtual 标记，便于后续删除。"
    fi
fi

if [ "$has_package_management" = false ]; then
    log_success "未检测到包管理器操作，或使用了预构建的轻量级镜像。"
elif [ "$WARNING_COUNT" -eq 0 ]; then
    log_success "包管理器缓存清理检查通过。"
fi

# 4. 检查临时文件清理
echo -e "\n[检查4]: 临时文件清理检查"
temp_file_patterns=("/tmp/" "/var/tmp/" "\\.tmp" "\\.log" "cache" "\\.cache")
cleanup_found=false

for pattern in "${temp_file_patterns[@]}"; do
    if grep -q "rm.*${pattern}" "${DOCKERFILE_PATH}"; then
        cleanup_found=true
        break
    fi
done

if grep -q -E "(wget|curl|pip install|npm install)" "${DOCKERFILE_PATH}" && [ "$cleanup_found" = false ]; then
    log_warning "检测到下载/安装操作但未发现临时文件清理。建议清理 /tmp、缓存文件等。"
    log_tip "示例: && rm -rf /tmp/* /var/tmp/* ~/.cache"
else
    log_success "临时文件清理检查通过或不适用。"
fi

# 5. 增强的 RUN 指令合并检查
echo -e "\n[检查5]: RUN 指令层数优化检查"
run_count=$(grep -c -E "^\s*RUN\s+" "${DOCKERFILE_PATH}")
if [ "$run_count" -gt 5 ]; then
    log_warning "检测到 ${run_count} 个 RUN 指令。过多的 RUN 指令会增加镜像层数。考虑使用 && 合并相关操作。"
    log_tip "将相关的命令合并，例如: RUN apt-get update && apt-get install -y package && apt-get clean"
elif [ "$run_count" -gt 0 ]; then
    log_success "RUN 指令数量合理 (${run_count} 个)。"
fi

# 6. 多阶段构建检查
echo -e "\n[检查6]: 多阶段构建检查"
from_count=$(grep -c -E "^\s*FROM\s+" "${DOCKERFILE_PATH}")
if [ "$from_count" -gt 1 ]; then
    log_success "检测到使用了多阶段构建 (${from_count} 个阶段)。这是减小镜像体积的最佳实践！"
    
    # 检查是否有命名的构建阶段
    if grep -q -E "FROM.*AS.*build" "${DOCKERFILE_PATH}"; then
        log_success "检测到命名的构建阶段，有利于构建优化。"
    fi
else
    if grep -q -E "(gcc|make|build-essential|npm install|pip install.*-r|go build|mvn|gradle)" "${DOCKERFILE_PATH}"; then
        log_warning "检测到编译/构建操作但未使用多阶段构建。强烈建议使用多阶段构建以减小最终镜像体积。"
        log_tip "使用构建阶段分离编译环境和运行环境，只保留运行时必需的文件。"
    else
        log_info "未检测到明显的编译操作，单阶段构建可能合适。"
    fi
fi

# 7. COPY/ADD 指令优化检查
echo -e "\n[检查7]: 文件复制指令优化检查"
copy_dot_found=false
if grep -q -E "^\s*(COPY|ADD)\s+\.\s+" "${DOCKERFILE_PATH}"; then
    copy_dot_found=true
    lines=$(grep -n -E "^\s*(COPY|ADD)\s+\.\s+" "${DOCKERFILE_PATH}" | cut -d: -f1 | tr '\n' ',' | sed 's/,$//')
    log_warning "检测到 'COPY .' 或 'ADD .' 指令 (行: ${lines})，这会复制整个构建上下文。"
    log_tip "考虑使用更精确的路径，或确保 .dockerignore 配置完善。"
fi

# 检查是否复制了不必要的文件类型
unnecessary_patterns=("\\.md" "test/" "tests/" "spec/" "docs/" "README" "LICENSE")
for pattern in "${unnecessary_patterns[@]}"; do
    if grep -q -E "^\s*(COPY|ADD).*${pattern}" "${DOCKERFILE_PATH}"; then
        log_warning "检测到复制了可能不必要的文件: ${pattern}。这些文件通常不需要在运行时镜像中。"
        break
    fi
done

if [ "$copy_dot_found" = false ]; then
    log_success "文件复制指令使用了具体路径，有利于控制镜像内容。"
fi

# 8. 环境变量和标签检查
echo -e "\n[检查8]: 镜像元数据检查"
if ! grep -q -E "^\s*LABEL\s+" "${DOCKERFILE_PATH}"; then
    log_info "建议添加 LABEL 指令来标记镜像版本、维护者等信息。"
fi

# 9. 端口暴露检查
echo -e "\n[检查9]: 端口暴露检查"
if ! grep -q -E "^\s*EXPOSE\s+" "${DOCKERFILE_PATH}"; then
    log_info "如果应用需要网络访问，建议使用 EXPOSE 指令声明端口。"
fi

# 10. 健康检查
echo -e "\n[检查10]: 健康检查"
if ! grep -q -E "^\s*HEALTHCHECK\s+" "${DOCKERFILE_PATH}"; then
    log_info "建议添加 HEALTHCHECK 指令以便容器编排系统监控应用健康状态。"
fi

# 11. 用户权限检查
echo -e "\n[检查11]: 用户权限检查"
if grep -q -E "^\s*USER\s+root" "${DOCKERFILE_PATH}"; then
    line_numbers=$(grep -n -E "^\s*USER\s+root" "${DOCKERFILE_PATH}" | cut -d: -f1 | tr '\n' ',' | sed 's/,$//')
    log_error "检测到明确使用 'USER root' (行: ${line_numbers})。生产镜像应使用非 root 用户运行。"
elif ! grep -q -E "^\s*USER\s+[^[:space:]]+" "${DOCKERFILE_PATH}"; then
    log_warning "未检测到 USER 指令。建议创建并切换到非 root 用户运行应用。"
else
    log_success "检测到非 root 用户配置。"
fi

# 12. ADD vs COPY 检查
echo -e "\n[检查12]: ADD vs COPY 指令检查"
if grep -q -E "^\s*ADD\s+" "${DOCKERFILE_PATH}" && ! grep -q -E "^\s*ADD\s+https?://" "${DOCKERFILE_PATH}"; then
    log_warning "检测到使用 ADD 指令复制本地文件。除非需要自动解压功能，否则建议使用 COPY。"
fi

if grep -q -E "^\s*ADD\s+https?://" "${DOCKERFILE_PATH}"; then
    log_warning "检测到 ADD 下载远程文件。建议使用 RUN curl/wget 以便进行错误处理和清理。"
fi

# --- 总结 ---
echo -e "\n======================================================"
echo "🐳 Dockerfile 镜像大小优化检查完成"
echo "发现 ${ERROR_COUNT} 个错误, ${WARNING_COUNT} 个警告"

if [ "${ERROR_COUNT}" -gt 0 ]; then
    echo "${RED}❌ 状态: 检查失败，存在严重问题需要修复${RESET}"
    exit_code=1
elif [ "${WARNING_COUNT}" -gt 0 ]; then
    echo "${YELLOW}⚠️  状态: 检查通过，但建议优化以进一步减小镜像体积${RESET}"
    exit_code=2  # 使用不同退出码区分警告和错误
else
    echo "${GREEN}✅ 状态: 检查完全通过，Dockerfile 已遵循镜像大小优化最佳实践${RESET}"
    exit_code=0
fi

echo -e "\n💡 镜像大小优化建议："
echo "  • 使用轻量级基础镜像 (alpine, slim)"
echo "  • 合并 RUN 指令减少镜像层数"
echo "  • 使用多阶段构建分离构建和运行环境"
echo "  • 及时清理包管理器缓存和临时文件"
echo "  • 配置完善的 .dockerignore 文件"
echo "  • 使用 --no-install-recommends 避免安装推荐包"

echo "======================================================"
exit $exit_code 