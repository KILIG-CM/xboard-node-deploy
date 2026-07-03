#!/usr/bin/env bash
# =============================================================================
# Xboard-Node 部署脚本
# 两种模式:
#   1) 交互输入 —— 一步步问, 自动生成 config.yml
#   2) 手动填写 —— 生成模板(或用已有的 config.yml), 你自己编辑后再跑, 脚本负责部署
# 默认配置 = JP 集群 (AnyTLS 48/49/50 + Hy2 51/52, sing-box 单容器)
# 用法:  curl -fsSL <raw_url>/deploy.sh | bash    或    bash deploy.sh
# =============================================================================
set -euo pipefail

C_G='\033[32m'; C_Y='\033[33m'; C_R='\033[31m'; C_0='\033[0m'
say(){ echo -e "${C_G}==>${C_0} $*"; }
warn(){ echo -e "${C_Y}!! $*${C_0}"; }
die(){ echo -e "${C_R}xx $*${C_0}" >&2; exit 1; }
# 从 /dev/tty 读, 这样 `curl ... | bash` 时仍能交互输入 (管道里 stdin=脚本本身)
ask(){ local p="$1" d="${2:-}" v; if [ -n "$d" ]; then read -rp "$p [$d]: " v </dev/tty; echo "${v:-$d}"; else read -rp "$p: " v </dev/tty; echo "$v"; fi; }
asks(){ local p="$1" v; read -rsp "$p: " v </dev/tty; echo >&2; echo "$v"; }  # 隐藏输入(密钥)

IMAGE="ghcr.io/kilig-cm/xboard-node:latest"
DEPLOY_DIR="$HOME/xboard-node"
CFG_DIR="$DEPLOY_DIR/config"
CFG_FILE="$CFG_DIR/config.yml"

echo "======================================================================"
echo "  Xboard-Node 部署向导  (Ctrl-C 退出)"
echo "======================================================================"

# ---------- 0. 选择配置方式 ----------
echo "请选择配置方式:"
echo "  1) 交互输入 —— 一步步问, 自动生成 config.yml (推荐)"
echo "  2) 手动填写 —— 生成模板/用已有的 config.yml, 你自己编辑后再跑"
MODE=$(ask "输入 1 或 2" "1")

# 默认节点 (JP 集群):  格式 node_id:domain:proto   proto ∈ {anytls|hy2|vless}
DEFAULT_NODES="48:sern6.kiligt.top:anytls 49:sern7.kiligt.top:anytls 50:sern8.kiligt.top:anytls 51:sern9.kiligt.top:hy2 52:sern10.kiligt.top:hy2"

if [ "$MODE" = "2" ]; then
  # ============ 手动模式 ============
  mkdir -p "$CFG_DIR"
  if [ -f "$CFG_FILE" ]; then
    say "检测到已有 config.yml: $CFG_FILE —— 将用它继续部署"
    echo "----- 当前 config.yml (证书 token 隐藏) -----"
    sed 's/CF_API_TOKEN:.*/CF_API_TOKEN: "***"/' "$CFG_FILE"
    echo "---------------------------------------------"
    GO=$(ask "确认用这个配置继续部署? (y/n)" "y")
    [ "$GO" = "y" ] || die "已取消。编辑好 $CFG_FILE 后重新运行。"
  else
    say "生成配置模板: $CFG_FILE"
    cat > "$CFG_FILE" <<'TPL'
# ===== Xboard-Node config.yml 模板 (手动填写) =====
# 填好后重新运行脚本, 选「2) 手动填写」, 会自动检测到本文件并部署。
# 内核: singbox = AnyTLS/Hy2/TUIC ; xray = VLESS/Reality
# DNS 证书节点(AnyTLS/Hy2)需要 cert 块; Reality 不需要 cert。
kernel:
  type: singbox
panel:
  url: https://sub.kiligt.top
  token: "在这里填面板通信密钥token"
nodes:
  - node_id: 48            # anytls - sern6
    cert:
      cert_mode: dns
      domain: sern6.kiligt.top
      email: kilig999110@gmail.com
      dns_provider: cloudflare
      dns_env:
        CF_API_TOKEN: "在这里填CloudflareAPIToken"
  - node_id: 49            # anytls - sern7
    cert:
      cert_mode: dns
      domain: sern7.kiligt.top
      email: kilig999110@gmail.com
      dns_provider: cloudflare
      dns_env:
        CF_API_TOKEN: "在这里填CloudflareAPIToken"
  - node_id: 50            # anytls - sern8
    cert:
      cert_mode: dns
      domain: sern8.kiligt.top
      email: kilig999110@gmail.com
      dns_provider: cloudflare
      dns_env:
        CF_API_TOKEN: "在这里填CloudflareAPIToken"
  - node_id: 51            # hy2 - sern9
    cert:
      cert_mode: dns
      domain: sern9.kiligt.top
      email: kilig999110@gmail.com
      dns_provider: cloudflare
      dns_env:
        CF_API_TOKEN: "在这里填CloudflareAPIToken"
  - node_id: 52            # hy2 - sern10
    cert:
      cert_mode: dns
      domain: sern10.kiligt.top
      email: kilig999110@gmail.com
      dns_provider: cloudflare
      dns_env:
        CF_API_TOKEN: "在这里填CloudflareAPIToken"
TPL
    echo
    say "模板已生成。请编辑它填入真实 token / 域名 / 节点:"
    echo "    nano $CFG_FILE"
    echo "填好后重新运行本脚本并再次选「2」即可继续部署。"
    exit 0
  fi
else
  # ============ 交互模式 ============
  # 1. 面板 / 密钥
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

  # 2. 节点列表
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

  # 3. 生成 config.yml
  say "生成 $CFG_FILE"
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
  } > "$CFG_FILE"
  echo "----- config.yml (证书 token 已写入, 下面隐藏) -----"
  sed 's/CF_API_TOKEN:.*/CF_API_TOKEN: "***"/' "$CFG_FILE"
  echo "---------------------------------------------------"
fi

# ---------- compose 文件 ----------
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

# ---------- 安装 docker ----------
if ! command -v docker >/dev/null 2>&1; then
  say "安装 Docker"
  curl -fsSL https://get.docker.com | sh
else
  say "Docker 已安装, 跳过"
fi

# ---------- 启动 ----------
say "拉镜像 + 启动"
docker pull "$IMAGE"
# 老容器可能占端口, 先清掉再起 (换内核时尤其必要)
docker rm -f xboard-node 2>/dev/null || true
cd "$DEPLOY_DIR"
docker compose up -d --force-recreate

# ---------- 自动检测监听端口 ----------
# 端口由面板按 node_id 下发, config 里没有; 从容器日志的 "[proto:port] started" 提取,
# 按协议分 TCP/UDP。 TCP: anytls/vless/trojan/vmess/ss ; UDP: hysteria2/hysteria/tuic
detect_ports(){
  local logs proto port
  TCP_PORTS=""; UDP_PORTS=""
  logs=$(docker compose logs 2>/dev/null || true)
  while IFS=: read -r proto port; do
    [ -z "${port:-}" ] && continue
    case "$proto" in
      hysteria2|hysteria|tuic) UDP_PORTS="$UDP_PORTS $port" ;;
      *)                       TCP_PORTS="$TCP_PORTS $port" ;;
    esac
  done < <(echo "$logs" | grep -iE 'started' \
             | grep -oiE '(anytls|vless|trojan|vmess|shadowsocks|hysteria2|hysteria|tuic):[0-9]+' \
             | sort -u)
  TCP_PORTS=$(echo $TCP_PORTS | tr ' ' '\n' | sort -un | tr '\n' ' ' | sed 's/ *$//')
  UDP_PORTS=$(echo $UDP_PORTS | tr ' ' '\n' | sort -un | tr '\n' ' ' | sed 's/ *$//')
}

say "等待节点启动并自动检测监听端口 (证书申请可能需要 1~2 分钟)..."
TCP_PORTS=""; UDP_PORTS=""
for i in $(seq 1 30); do          # 最多轮询 ~150s
  detect_ports
  [ -n "$TCP_PORTS$UDP_PORTS" ] && break
  sleep 5
done

if [ -n "$TCP_PORTS$UDP_PORTS" ]; then
  say "检测到监听端口:  TCP=[$TCP_PORTS]  UDP=[$UDP_PORTS]"
else
  warn "未能自动检测到端口(证书还在申请/节点没起来/日志格式不符), 改为手动输入"
  TCP_PORTS=$(ask "要放行的 TCP 端口(空格分隔, AnyTLS/VLESS)" "2053 2083 2087")
  UDP_PORTS=$(ask "要放行的 UDP 端口(空格分隔, Hy2)" "2096 8443")
fi

# ---------- 防火墙 ----------
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

# ---------- 自检 ----------
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
