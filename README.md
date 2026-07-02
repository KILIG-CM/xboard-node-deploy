# xboard-node-deploy

Xboard-Node 一键交互式部署脚本。在任意新 VPS 上运行，逐项输入即可完成：
生成 config → 安装 Docker → 开放防火墙端口 → 拉取镜像 → 启动容器 → 自检。

## 使用

```bash
bash deploy.sh
```

每一项都有默认值（直接回车即用 JP 集群默认：AnyTLS 48/49/50 + Hy2 51/52，sing-box 单容器）。
密钥类输入（面板 token、Cloudflare API Token）为隐藏输入，不写入脚本。

## 换集群

- **JP（AnyTLS + Hy2）**：内核 `singbox`，证书模式 `dns`，节点 proto 填 `anytls` / `hy2`。
- **HK（VLESS + Reality）**：内核 `xray`，证书模式 `none`（Reality 免证书），节点 proto 填 `vless`。

## 部署后手动步骤

1. 面板对应节点变绿。
2. Cloudflare 加 A 记录（灰云 DNS-only）把本机 IP 加进轮询池：
   - AnyTLS/VLESS (TCP) 域名 → 全部 IP
   - Hy2 (UDP) 域名 → 仅 UDP 通的 IP
3. 客户端重新拉取订阅才生效。

镜像：`ghcr.io/kilig-cm/xboard-node:latest`（自建，含较新 Xray + sing-box）。
