#!/usr/bin/env bash
# =============================================================================
# Xboard-Node 交互式部署脚本
# 在任意新 VPS 上运行, 逐项输入 -> 生成 config -> 装 docker -> 开端口 -> 起容器
# 默认配置 = JP 集群 (AnyTLS 48/49/50 + Hy2 51/52, sing-box 单容器)
# 用法:  curl -fsSL <raw_url>/deploy.sh | bash    或    bash deploy.sh
# =============================================================================
set -euo pipefail

C_G='\033[32m'; C_Y='\033[33m'; C_R='\033[31m'; C_0='\033[0m'
say(){ echo -e "${C_G}==>${C_0} $*"; }
warn(){ echo -e "${C_Y}!! $*${C_0}"; }
die(){ echo -e "${C_R}xx $*${C_0}" >&2; exit 1; }
ask(){ local p="$1" d="${2:-}" v; if [ -n "$d" ]; then read -rp "$p [$d]: " v; echo "${v:-$d}"; else read -rp "$p: " v; echo "$v"; fi; }
asks(){ local p="$1" v; read -rsp "$p: " v; echo >&2; echo "$v"; }  # 隐藏输入(密钥)

IMAGE="ghcr.io/kilig-cm/xboard-node:latest"
DEPLOY_DIR="$HOME/xboard-node"
CFG_DIR="$DEPLOY_DIR/config"

echo "======================================================================"
echo "  Xboard-Node 部署向导  (Ctrl-C 退出)"
echo "======================================================================"

# ---------- 1. 面板 / 密钥 ----------
PANEL_URL=$(ask "面板地址" "https://sub.kiligt.top")
PANEL_TOKEN=$(asks "面板通信密钥 token (输入隐藏)")
[ -n "$PANEL_TOKEN" ] || die "面板 token 不能为空"
EMAIL=$(ask "证书申请邮箱" "kilig999110@gmail.com")
KERNEL=$(ask "内核 type (singbox=AnyTLS/Hy2/TUIC, xray=VLESS/Reality)" "singbox")

CERT_MODE=$(ask "证书模式 (dns=需要真实证书 / none=Reality 免证书)" "dns")
CF_TOKEN=""
if [ "$CERT_MODE" = "dns" ]; then
  CF_TOKEN=$(asks "Cloudflare API Token (输入隐藏)")
  [ -n "$CF_TOKEN" ] || die "dns 证书模式必须提供 Cloudflare token"
fi

# ---------- 2. 节点列表 ----------
# 格式: node_id:domain:proto   proto ∈ {anytls|hy2|vless}  (vless=Reality 走 xray+none)
DEFAULT_NODES="48:sern6.kiligt.top:anytls 49:sern7.kiligt.top:anytls 50:sern8.kiligt.top:anytls 51:sern9.kiligt.top:hy2 52:sern10.kiligt.top:hy2"
echo
echo "默认节点 (JP 集群):"
echo "  $DEFAULT_NODES" | tr ' ' '\n' | sed 's/^/    /'
USE_DEF=$(ask "用默认节点? (y/n)" "y")
if [ "$USE_DEF" = "y" ]; then
  NODES="$DEFAULT_NODES"
else
  echo "逐个输入节点, 空行结束。格式  node_id:domain:proto  (proto=anytls|hy2|vless)"
  NODES=""
  while true; do
    line=$(ask "节点" ""); [ -z "$line" ] && break; NODES="$NODES $line"
  done
  [ -n "$NODES" ] || die "至少要一个节点"
fi

# ---------- 3. 端口 (仅用于防火墙放行) ----------
TCP_PORTS=$(ask "要放行的 TCP 端口(空格分隔, AnyTLS/VLESS)" "2053 2083 2087")
UDP_PORTS=$(ask "要放行的 UDP 端口(空格分隔, Hy2)" "2096 8443")

# ---------- 4. 生成 config.yml ----------
say "生成 $CFG_DIR/config.yml"
mkdir -p "$CFG_DIR"
{
  echo "kernel:"
  echo "  type: $KERNEL"
  echo "panel:"
  echo "  url: $PANEL_URL"
  echo "  token: $PANEL_TOKEN"
  echo "nodes:"
  for n in $NODES; do
    id="${n%%:*}"; rest="${n#*:}"; domain="${rest%%:*}"; proto="${rest##*:}"
    echo "  - node_id: $id            # $proto - $domain"
    if [ "$CERT_MODE" = "dns" ]; then
      echo "    cert:"
      echo "      cert_mode: dns"
      echo "      domain: $domain"
      echo "      email: $EMAIL"
      echo "      dns_provider: cloudflare"
      echo "      dns_env:"
      echo "        CF_API_TOKEN: \"$CF_TOKEN\""
    fi
  done
} > "$CFG_DIR/config.yml"
echo "----- config.yml (证书 token 已写入, 下面隐藏) -----"
sed 's/CF_API_TOKEN:.*/CF_API_TOKEN: "***"/' "$CFG_DIR/config.yml"
echo "---------------------------------------------------"

# ---------- 5. compose 文件 ----------
if [ ! -f "$DEPLOY_DIR/compose.yaml" ] && [ ! -f "$DEPLOY_DIR/docker-compose.yml" ]; then
  say "生成 compose.yaml"
  cat > "$DEPLOY_DIR/compose.yaml" <<EOF
services:
  xboard-node:
    image: $IMAGE
    container_name: xboard-node
    restart: always
    network_mode: host
    volumes:
      - ./config:/etc/xboard-node
EOF
else
  say "已存在 compose 文件, 仅确保镜像指向自建镜像"
  sed -i "s#ghcr.io/cedar2025/xboard-node:latest#$IMAGE#" "$DEPLOY_DIR"/*.y*ml 2>/dev/null || true
fi

# ---------- 6. 安装 docker ----------
if ! command -v docker >/dev/null 2>&1; then
  say "安装 Docker"
  curl -fsSL https://get.docker.com | sh
else
  say "Docker 已安装, 跳过"
fi

# ---------- 7. 防火墙 ----------
if command -v ufw >/dev/null 2>&1; then
  echo "即将用 ufw 放行:  TCP=[$TCP_PORTS]  UDP=[$UDP_PORTS]"
  DO_FW=$(ask "是否放行以上端口? (y/n)" "y")
  if [ "$DO_FW" = "y" ]; then
    say "放行端口 (ufw)"
    for p in $TCP_PORTS; do ufw allow "${p}/tcp" || true; done
    for p in $UDP_PORTS; do ufw allow "${p}/udp" || true; done
  else
    warn "已跳过 ufw 放行, 请自行确保端口可达"
  fi
else
  warn "未检测到 ufw, 跳过系统防火墙放行"
fi
warn "别忘了云厂商安全组也放行上述 TCP + UDP 端口"

# ---------- 8. 启动 ----------
say "拉镜像 + 启动"
docker pull "$IMAGE"
# 老容器可能占端口, 先清掉再起 (换内核时尤其必要)
docker rm -f xboard-node 2>/dev/null || true
cd "$DEPLOY_DIR"
docker compose up -d --force-recreate

# ---------- 9. 自检 ----------
say "容器镜像: $(docker inspect xboard-node --format '{{.Image}}' 2>/dev/null || echo '未起来')"
say "启动日志 (最后 40 行):"
docker compose logs --tail=40

cat <<'NOTE'

======================== 部署后手动步骤 ========================
1. 面板里对应节点变绿。
2. Cloudflare 加 A 记录 (灰云 DNS-only), 把本机 IP 加进轮询池:
     AnyTLS/VLESS (TCP) 域名 -> 全部 IP
     Hy2 (UDP)          域名 -> 仅 UDP 通的 IP
3. 客户端重新拉取订阅才生效。
==============================================================
NOTE
