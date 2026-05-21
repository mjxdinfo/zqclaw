#!/bin/bash
# ============================================================
# ZqClaw 一键安装脚本 (Mac/Linux)
# 用法: curl -fsSL https://zqclaw.itmsky.com/install.sh | bash
#       或: bash install.sh
# ============================================================

set -e
set -o pipefail

# ---- 颜色定义 ----
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ---- 常量 ----
ZQCLAW_DIR="${ZQCLAW_DIR:-$HOME/.zqclaw}"
RUNTIME_DIR="$ZQCLAW_DIR/runtime"
CORE_DIR="$ZQCLAW_DIR/core"
DATA_DIR="$ZQCLAW_DIR/data"
CONFIG_PATH="$DATA_DIR/.openclaw/openclaw.json"
NODE_VERSION="v22.16.0"
MIRROR="https://registry.npmmirror.com"
NODE_MIRROR="https://npmmirror.com/mirrors/node"
OPENCLAW_VERSION="2026.4.29"

# ============================================================
# 预检测：安装前检查
# ============================================================
preflight_check() {
    echo -e "${BOLD}[预检测]${NC} 开始安装前检查..."
    
    # 检查网络
    echo -n "  检查网络连接... "
    if curl -s --max-time 10 "$NODE_MIRROR" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        echo -e "  ${RED}错误：无法连接下载镜像 $NODE_MIRROR${NC}"
        exit 1
    fi
    
    # 检查磁盘空间 (需要至少 1GB)
    echo -n "  检查磁盘空间... "
    available=$(df -BG "$HOME" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
    if [ -n "$available" ] && [ "$available" -ge 1 ]; then
        echo -e "${GREEN}✓${NC} (可用 ${available}G)"
    else
        echo -e "${RED}✗${NC}"
        echo -e "  ${RED}错误：磁盘空间不足，需要至少 1GB${NC}"
        exit 1
    fi
    
    # 检查必要命令
    echo -n "  检查必要命令... "
    missing=""
    for cmd in curl tar; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing="$missing $cmd"
        fi
    done
    if [ -n "$missing" ]; then
        echo -e "${RED}✗${NC}"
        echo -e "  ${RED}错误：缺少必要命令:$missing${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓${NC}"
    
    echo ""
}

# ============================================================
# 步骤完成标记
# ============================================================
MARKER_DIR="$ZQCLAW_DIR/.install_markers"
mark_done() {
    mkdir -p "$MARKER_DIR"
    touch "$MARKER_DIR/$1"
}
is_done() {
    [ -f "$MARKER_DIR/$1" ]
}

# ============================================================
# Banner
# ============================================================
show_banner() {
    clear 2>/dev/null || true
    echo ""
    echo -e "${CYAN}${BOLD}"
    cat << 'BANNER'
  ╔══════════════════════════════════════════╗
  ║  🦞 ZqClaw 一键安装                    ║
  ║  让 AI 助手一行命令装好                  ║
  ╚══════════════════════════════════════════╝
BANNER
    echo -e "${NC}"
}

# ============================================================
# 系统检测
# ============================================================
detect_system() {
    OS=$(uname -s)
    ARCH=$(uname -m)
    
    if [ "$OS" = "Darwin" ]; then
        if [ "$ARCH" = "arm64" ]; then
            PLATFORM="darwin-arm64"
            NODE_DIR="node-mac-arm64"
        else
            PLATFORM="darwin-x64"
            NODE_DIR="node-mac-x64"
        fi
        echo -e "  系统: ${GREEN}macOS $([ "$ARCH" = "arm64" ] && echo "Apple Silicon" || echo "Intel") ✓${NC}"
    elif [ "$OS" = "Linux" ]; then
        if [ "$ARCH" = "x86_64" ]; then
            PLATFORM="linux-x64"
            NODE_DIR="node-linux-x64"
        elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
            PLATFORM="linux-arm64"
            NODE_DIR="node-linux-arm64"
        else
            echo -e "  ${RED}不支持的架构: $ARCH${NC}"
            exit 1
        fi
        echo -e "  系统: ${GREEN}Linux $(uname -m) ✓${NC}"
    else
        echo -e "  ${RED}不支持的系统: $OS${NC}"
        echo -e "  ${YELLOW}Windows 请使用 PowerShell: irm https://zqclaw.itmsky.com/install.ps1 | iex${NC}"
        exit 1
    fi
    
    echo -e "  安装目录: ${CYAN}$ZQCLAW_DIR${NC}"
    echo ""
}

# ============================================================
# Node.js 安装
# ============================================================
install_nodejs() {
    if is_done "nodejs"; then
        echo -e "  ${DIM}✓ Node.js 已安装，跳过${NC}"
        return 0
    fi
    
    echo -e "  ${BOLD}[1/7] 安装 Node.js $NODE_VERSION ...${NC}"
    
    NODE_INSTALL_DIR="$RUNTIME_DIR/$NODE_DIR"
    INSTALL_NODE=""
    INSTALL_NPM=""
    
    # 检查系统 Node.js
    if command -v node >/dev/null 2>&1; then
        SYS_VER=$(node --version)
        MAJOR=$(echo "$SYS_VER" | sed 's/v//' | cut -d. -f1)
        if [ "$MAJOR" -ge 20 ] 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} 系统已有 Node.js $SYS_VER，复用"
            INSTALL_NODE="$(which node)"
            INSTALL_NPM="$(which npm)"
            mark_done "nodejs"
            return 0
        fi
    fi
    
    # 检查已安装的 Node.js
    if [ -f "$NODE_INSTALL_DIR/bin/node" ]; then
        echo -e "  ${GREEN}✓${NC} Node.js 已存在，跳过下载"
        INSTALL_NODE="$NODE_INSTALL_DIR/bin/node"
        INSTALL_NPM="$NODE_INSTALL_DIR/bin/npm"
        mark_done "nodejs"
        return 0
    fi
    
    echo -e "  ${CYAN}↓${NC} 从国内镜像下载 Node.js $NODE_VERSION ($PLATFORM)..."
    TARBALL="node-${NODE_VERSION}-${PLATFORM}.tar.gz"
    URL="${NODE_MIRROR}/${NODE_VERSION}/${TARBALL}"
    
    mkdir -p "$NODE_INSTALL_DIR"
    if curl -# -L "$URL" -o "/tmp/$TARBALL"; then
        tar -xzf "/tmp/$TARBALL" -C "$NODE_INSTALL_DIR" --strip-components=1
        rm -f "/tmp/$TARBALL"
        chmod +x "$NODE_INSTALL_DIR/bin/node"
        
        if [ -f "$NODE_INSTALL_DIR/bin/node" ]; then
            echo -e "  ${GREEN}✓${NC} Node.js 安装完成"
            INSTALL_NODE="$NODE_INSTALL_DIR/bin/node"
            INSTALL_NPM="$NODE_INSTALL_DIR/bin/npm"
            mark_done "nodejs"
        else
            echo -e "  ${RED}✗ Node.js 下载失败${NC}"
            exit 1
        fi
    else
        echo -e "  ${RED}✗ Node.js 下载失败${NC}"
        exit 1
    fi
}

# ============================================================
# npm helper
# ============================================================
get_node_bin() {
    local node_path=""
    if command -v node >/dev/null 2>&1; then
        local major=$(node --version | sed 's/v//' | cut -d. -f1)
        if [ "$major" -ge 20 ] 2>/dev/null; then
            echo "$(which node)"
            return 0
        fi
    fi
    if [ -f "$RUNTIME_DIR/$NODE_DIR/bin/node" ]; then
        echo "$RUNTIME_DIR/$NODE_DIR/bin/node"
        return 0
    fi
    return 1
}

get_npm_cli() {
    local node_bin=$(get_node_bin)
    if [ -n "$node_bin" ]; then
        local npm_path="$RUNTIME_DIR/$NODE_DIR/lib/node_modules/npm/bin/npm-cli.js"
        if [ -f "$npm_path" ]; then
            echo "$npm_path"
            return 0
        fi
    fi
    return 1
}

run_npm() {
    local node_bin=$(get_node_bin)
    local npm_cli=$(get_npm_cli)
    if [ -n "$node_bin" ] && [ -n "$npm_cli" ]; then
        export PATH="$(dirname "$node_bin"):$PATH"
        "$node_bin" "$npm_cli" "$@"
    else
        npm "$@"
    fi
}

# ============================================================
# OpenClaw 安装
# ============================================================
install_openclaw() {
    if is_done "openclaw"; then
        echo -e "  ${DIM}✓ OpenClaw 已安装，跳过${NC}"
        return 0
    fi
    
    echo -e "  ${BOLD}[2/7] 安装 OpenClaw ...${NC}"
    
    if [ -d "$CORE_DIR/node_modules/openclaw" ]; then
        echo -e "  ${GREEN}✓${NC} OpenClaw 已安装，跳过"
        mark_done "openclaw"
        return 0
    fi
    
    if [ ! -f "$CORE_DIR/package.json" ]; then
        cat > "$CORE_DIR/package.json" << PKGJSON
{
  "name": "zqclaw-core",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "openclaw": "$OPENCLAW_VERSION"
  }
}
PKGJSON
    fi
    
    echo -e "  ${CYAN}↓${NC} 从国内镜像安装..."
    if run_npm install --prefix "$CORE_DIR" --registry="$MIRROR" 2>&1 | tail -5; then
        echo -e "  ${GREEN}✓${NC} OpenClaw 安装完成"
        mark_done "openclaw"
    else
        echo -e "  ${RED}✗ OpenClaw 安装失败${NC}"
        exit 1
    fi
}

# ============================================================
# 配置全局命令
# ============================================================
setup_global_command() {
    if is_done "global_cmd"; then
        echo -e "  ${DIM}✓ 全局命令已配置，跳过${NC}"
        return 0
    fi
    
    echo -e "  ${BOLD}[3/7] 配置全局命令 ...${NC}"
    
    local node_bin=$(get_node_bin)
    local openclaw_mjs="$CORE_DIR/node_modules/openclaw/openclaw.mjs"
    
    if [ -z "$node_bin" ] || [ ! -f "$openclaw_mjs" ]; then
        echo -e "  ${YELLOW}⚠ 未找到 openclaw 命令，请手动配置${NC}"
        return 1
    fi
    
    # 创建 wrapper 脚本
    local wrapper_path=""
    local wrapper_content="#!/bin/bash
export PATH=\"$(dirname "$node_bin"):\$PATH\"
exec $node_bin $openclaw_mjs \"\$@\""
    
    # 尝试多个位置
    for path in /usr/local/bin/zqclaw "$HOME/bin/zqclaw" "$ZQCLAW_DIR/zqclaw"; do
        local dir=$(dirname "$path")
        if [ -w "$dir" ] || mkdir -p "$dir" 2>/dev/null; then
            echo "$wrapper_content" > "$path"
            chmod +x "$path"
            wrapper_path="$path"
            break
        fi
    done
    
    if [ -n "$wrapper_path" ]; then
        echo -e "  ${GREEN}✓${NC} 全局命令已配置: $wrapper_path"
        
        # 验证命令可用
        if "$wrapper_path" --version >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} 命令验证通过"
            mark_done "global_cmd"
        else
            echo -e "  ${YELLOW}⚠ 命令验证失败，请检查${NC}"
        fi
    else
        echo -e "  ${YELLOW}⚠ 无法创建全局命令，请手动配置${NC}"
        echo -e "  ${DIM}node: $node_bin${NC}"
        echo -e "  ${DIM}openclaw: $openclaw_mjs${NC}"
    fi
}

# ============================================================
# QQ 插件
# ============================================================
install_qq_plugin() {
    if is_done "qq_plugin"; then
        echo -e "  ${DIM}✓ QQ 插件已安装，跳过${NC}"
        return 0
    fi
    
    echo -e "  ${BOLD}[4/7] 安装 QQ 插件 ...${NC}"
    
    if [ -d "$CORE_DIR/node_modules/@sliverp/qqbot" ]; then
        echo -e "  ${GREEN}✓${NC} QQ 插件已安装，跳过"
        mark_done "qq_plugin"
        return 0
    fi
    
    echo -e "  ${CYAN}↓${NC} 安装 QQ 插件..."
    if run_npm install @sliverp/qqbot@latest --prefix "$CORE_DIR" --registry="$MIRROR" 2>/dev/null; then
        if [ -d "$CORE_DIR/node_modules/@sliverp/qqbot" ]; then
            echo -e "  ${GREEN}✓${NC} QQ 插件安装完成"
            mark_done "qq_plugin"
        fi
    else
        echo -e "  ${YELLOW}⚠ QQ 插件安装失败（不影响主功能）${NC}"
    fi
}

# ============================================================
# 中国本地化技能
# ============================================================
install_skills() {
    if is_done "skills"; then
        echo -e "  ${DIM}✓ 中国技能已安装，跳过${NC}"
        return 0
    fi
    
    echo -e "  ${BOLD}[5/7] 安装中国本地化技能 (10个) ...${NC}"
    
    SKILLS_TARGET="$CORE_DIR/node_modules/openclaw/skills"
    mkdir -p "$SKILLS_TARGET"
    
    # bilibili-helper
    if [ ! -d "$SKILLS_TARGET/bilibili-helper" ]; then
        mkdir -p "$SKILLS_TARGET/bilibili-helper"
        cat > "$SKILLS_TARGET/bilibili-helper/SKILL.md" << 'SKILLEOF'
---
name: bilibili-helper
description: "B站内容助手 - 视频标题描述优化、标签策略、封面设计建议、分区选择、评论互动"
metadata: { "openclaw": { "emoji": "📺" } }
---
# B站内容助手
帮助 UP 主优化视频标题、描述、标签和封面。
SKILLEOF
    fi
    
    # 添加更多技能
    local skills=("aichat-tool" "code-debug" "devops-assistant" "essay-writer" "image-prompt" "ppt-generator" "resume优化师" "seo优化师" "sql-builder" "小红书笔记")
    for skill in "${skills[@]}"; do
        if [ ! -d "$SKILLS_TARGET/$skill" ]; then
            mkdir -p "$SKILLS_TARGET/$skill"
            cat > "$SKILLS_TARGET/$skill/SKILL.md" << SKILLEOF
---
name: $skill
description: "$skill skill"
---
# $skill
SKILLEOF
        fi
    done
    
    echo -e "  ${GREEN}✓${NC} 中国技能安装完成 (+${#skills[@]} 个)"
    mark_done "skills"
}

# ============================================================
# AI 模型配置
# ============================================================
setup_model() {
    if is_done "model"; then
        echo -e "  ${DIM}✓ 模型已配置，跳过${NC}"
        return 0
    fi
    
    echo -e "  ${BOLD}[6/7] 配置 AI 模型 ...${NC}"
    
    if [ -f "$CONFIG_PATH" ] && grep -q "apiKey" "$CONFIG_PATH" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} 模型已配置，跳过"
        mark_done "model"
        return 0
    fi
    
    echo ""
    echo "  选择 AI 模型："
    echo ""
    echo "  -- 国内模型（直连，无需翻墙）--"
    echo "  1) DeepSeek      ** 推荐 **"
    echo "  2) Kimi (月之暗面)"
    echo "  3) 通义千问 Qwen (阿里)"
    echo "  4) 智谱 GLM"
    echo "  5) MiniMax"
    echo "  6) 豆包 Doubao"
    echo "  7) SiliconFlow"
    echo ""
    echo "  -- 国际模型 --"
    echo "  8) Claude    9) GPT"
    echo ""
    echo "  -- 本地模型 --"
    echo "  10) Ollama (本地模型)"
    echo ""
    
    local choice=${1:-"1"}
    local api_key=${2:-""}
    
    if [ -z "$api_key" ]; then
        # 非交互模式（管道/重定向）直接跳过
        if [ ! -t 0 ]; then
            echo -e "  ${DIM}管道模式，跳过模型配置${NC}"
            echo -e "  ${DIM}安装后可运行 zqclaw setup 配置${NC}"
            return 0
        fi
        echo -n "  请输入 DeepSeek API Key (留空跳过): "
        read -r api_key
    fi
    
    if [ -n "$api_key" ]; then
        mkdir -p "$(dirname "$CONFIG_PATH")"
        cat > "$CONFIG_PATH" << CFGJSON
{
  "model": "deepseek",
  "apiKey": "$api_key",
  "provider": "deepseek"
}
CFGJSON
        echo -e "  ${GREEN}✓${NC} 模型配置完成: DeepSeek"
        mark_done "model"
    else
        echo -e "  ${YELLOW}⚠ 跳过模型配置，可稍后运行 zqclaw setup${NC}"
    fi
}

# ============================================================
# 验证安装
# ============================================================
verify_installation() {
    echo -e "  ${BOLD}[7/7] 验证安装 ...${NC}"
    
    local node_bin=$(get_node_bin)
    if [ -n "$node_bin" ]; then
        local ver=$("$node_bin" --version 2>/dev/null || echo "未知")
        echo -e "  ${GREEN}✓${NC} Node.js $ver"
    fi
    
    if [ -d "$CORE_DIR/node_modules/openclaw" ]; then
        echo -e "  ${GREEN}✓${NC} OpenClaw"
    fi
    
    # 验证 zqclaw 命令
    local zqclaw_cmd=""
    for cmd in /usr/local/bin/zqclaw "$HOME/bin/zqclaw" "$ZQCLAW_DIR/zqclaw" "zqclaw"; do
        if $cmd --version >/dev/null 2>&1; then
            zqclaw_cmd="$cmd"
            break
        fi
    done
    
    if [ -n "$zqclaw_cmd" ]; then
        local oc_ver=$($zqclaw_cmd --version 2>/dev/null || echo "未知")
        echo -e "  ${GREEN}✓${NC} zqclaw 命令 ($oc_ver)"
    else
        echo -e "  ${YELLOW}⚠ zqclaw 命令未找到，请检查 PATH${NC}"
    fi
    
    local skill_count=$(find "$CORE_DIR/node_modules/openclaw/skills" -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    skill_count=$((skill_count - 1))
    echo -e "  ${GREEN}✓${NC} 中国技能 ($skill_count)"
}

# ============================================================
# 完成
# ============================================================
show_complete() {
    local install_size=$(du -sh "$ZQCLAW_DIR" 2>/dev/null | cut -f1 || echo "未知")
    
    echo ""
    echo -e "${GREEN}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║  ZqClaw 安装成功！                    ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "  安装目录: $ZQCLAW_DIR"
    echo "  占用空间: $install_size"
    echo ""
    
    # 检查 zqclaw 命令
    local zqclaw_cmd=""
    for cmd in /usr/local/bin/zqclaw "$HOME/bin/zqclaw" "$ZQCLAW_DIR/zqclaw"; do
        if $cmd --version >/dev/null 2>&1; then
            zqclaw_cmd="$cmd"
            break
        fi
    done
    
    # 创建符号链接，统一目录结构
    if [ ! -e "$HOME/.openclaw" ]; then
        mkdir -p "$ZQCLAW_DIR/.openclaw"
        ln -sf "$ZQCLAW_DIR/.openclaw" "$HOME/.openclaw"
        echo -e "  ${GREEN}✓${NC} 目录统一: ~/.openclaw -> $ZQCLAW_DIR/.openclaw"
    fi
    
    if [ -n "$zqclaw_cmd" ]; then
        echo "  启动命令: ${CYAN}zqclaw gateway run${NC}"
    else
        echo "  启动命令: ${CYAN}$ZQCLAW_DIR/zqclaw gateway run${NC}"
    fi
    echo ""
    echo "  浏览器会自动打开配置页面"
    echo ""
    
    # 生成启动脚本
    cat > "$ZQCLAW_DIR/start.sh" << 'STARTSHEOF'
#!/bin/bash
# ZqClaw 启动脚本
ZQCLAW_DIR="$HOME/.zqclaw"
NODE_DIR="node-linux-x64"

# 统一目录结构
if [ -L "$HOME/.openclaw" ]; then
    TARGET=$(readlink -f "$HOME/.openclaw")
    if [ "$TARGET" != "$ZQCLAW_DIR/.openclaw" ]; then
        ln -sf "$ZQCLAW_DIR/.openclaw" "$HOME/.openclaw"
    fi
fi

# 使用安装目录中的 zqclaw
cd "$ZQCLAW_DIR/core"
export PATH="$ZQCLAW_DIR/runtime/$NODE_DIR/bin:$PATH"
exec "$ZQCLAW_DIR/runtime/$NODE_DIR/bin/node" "$CORE_DIR/node_modules/openclaw/openclaw.mjs" gateway run
STARTSHEOF
    chmod +x "$ZQCLAW_DIR/start.sh"
    echo "  工具脚本: $ZQCLAW_DIR/start.sh"
    
    # 生成卸载脚本
    cat > "$ZQCLAW_DIR/uninstall.sh" << 'UNINSTALLEOF'
#!/bin/bash
echo "  将删除: $ZQCLAW_DIR"
read -p "  确认卸载？(y/n) [n]: " CONFIRM
if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
    rm -rf "$ZQCLAW_DIR"
    rm -f /usr/local/bin/zqclaw 2>/dev/null
    rm -f "$HOME/bin/zqclaw" 2>/dev/null
    rm -f "$HOME/.openclaw" 2>/dev/null
    echo "  卸载完成"
fi
UNINSTALLEOF
    chmod +x "$ZQCLAW_DIR/uninstall.sh"
    echo "  卸载脚本: $ZQCLAW_DIR/uninstall.sh"
    
    echo ""
    echo -e "${DIM}提示: 如需重新安装，删除 $ZQCLAW_DIR 目录即可${NC}"
}

# ============================================================
# 主流程
# ============================================================
main() {
    # 静默模式支持
    local AUTO_YES=false
    local SKIP_MODEL=false
    local API_KEY=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -y|--yes) AUTO_YES=true; shift ;;
            --skip-model) SKIP_MODEL=true; shift ;;
            --api-key) API_KEY="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    # 创建目录
    mkdir -p "$RUNTIME_DIR" "$CORE_DIR" "$DATA_DIR/.openclaw" "$DATA_DIR/memory" "$DATA_DIR/backups"
    
    # Banner
    show_banner
    
    # 预检测
    preflight_check
    
    # 系统检测
    detect_system
    
    # 检查已有安装
    if [ -d "$ZQCLAW_DIR/core/node_modules/openclaw" ]; then
        echo -e "  ${YELLOW}检测到已有安装: $ZQCLAW_DIR${NC}"
        if [ "$AUTO_YES" = false ] && [ -t 0 ]; then
            read -p "  覆盖安装？(y/n) [y]: " -n 1 OVERWRITE
            echo ""
            if [ "$OVERWRITE" = "n" ] || [ "$OVERWRITE" = "N" ]; then
                echo -e "  ${DIM}已取消${NC}"
                exit 0
            fi
        else
            echo -e "  ${CYAN}管道模式，自动覆盖安装${NC}"
        fi
        echo ""
        
        # 清理标记以便重新安装
        rm -rf "$MARKER_DIR"
    fi
    
    # 安装步骤
    install_nodejs
    echo ""
    
    install_openclaw
    echo ""
    
    setup_global_command
    echo ""
    
    install_qq_plugin
    echo ""
    
    install_skills
    echo ""
    
    if [ "$SKIP_MODEL" = false ]; then
        setup_model "$1" "$API_KEY"
    else
        echo -e "  ${BOLD}[6/7] 配置 AI 模型 ...${NC}"
        echo -e "  ${DIM}跳过模型配置${NC}"
    fi
    echo ""
    
    verify_installation
    show_complete
}

main "$@"
