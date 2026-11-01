#!/usr/bin/env bash
# 抓取并合并免费节点订阅，生成 clash.yaml 与 v2ray.txt
# 任一环节失败（网络、转换服务、返回空内容）都会以非 0 退出，避免把空文件提交到仓库
set -euo pipefail

CLASH_FILE="clash.yaml"
V2RAY_FILE="v2ray.txt"
CLASH_TMP=".clash.yaml.tmp"
V2RAY_TMP=".v2ray.txt.tmp"

cleanup() {
  rm -f "$CLASH_TMP" "$V2RAY_TMP"
}
trap cleanup EXIT

# 上游源；proxy.v2gh.com 前缀已失效（会返回 HTML 错误页），这里直连 raw
PAWDROID_SUB="https://raw.githubusercontent.com/Pawdroid/Free-servers/main/sub"

# 两个上游源用 %7C（即 |）分隔，由订阅转换服务合并；scv=false 保留证书校验
SUBSCRIBE_COMMON="url=https%3A%2F%2Fraw.githubusercontent.com%2FPawdroid%2FFree-servers%2Fmain%2Fsub%7Chttps%3A%2F%2Fraw.githubusercontent.com%2Fermaozi01%2Ffree_clash_vpn%2Fmain%2Fsubscribe%2Fclash.yml&insert=false&config=https%3A%2F%2Fraw.githubusercontent.com%2FNZESupB%2FProfile%2Fmain%2Foutpref%2Fpypref%2Fpyfull.ini&filename=GitHub-GetNode&append_type=true&emoji=true&list=false&tfo=false&scv=false&fdn=false&sort=true&udp=true&new_name=true"

SUBSCRIBE_CLASH="https://pub-api-1.bianyuan.xyz/sub?target=clash&${SUBSCRIBE_COMMON}"

# bianyuan 转换服务对 target=v2ray 恒返回空内容（实测 200/0 字节），
# 因此 v2ray 订阅直接取上游 base64 编码的订阅
SUBSCRIBE_V2RAY="$PAWDROID_SUB"

# 优先用 wget；环境里没有 wget 时（例如 Git Bash）自动改用 curl
fetch() {
  local url="$1"
  local out="$2"

  if command -v wget >/dev/null 2>&1; then
    wget -q --tries=3 --retry-connrefused --timeout=30 -O "$out" "$url"
  else
    curl -fsSL --retry 3 --connect-timeout 10 --max-time 60 -o "$out" "$url"
  fi
}

# 下载订阅到临时文件；失败或内容为空时返回非 0
download() {
  local url="$1"
  local out="$2"
  local label="$3"

  echo "正在获取 ${label} ..."
  if ! fetch "$url" "$out"; then
    echo "错误：${label} 下载失败，请检查网络或订阅转换服务状态" >&2
    return 1
  fi
  if [ ! -s "$out" ]; then
    echo "错误：${label} 返回内容为空" >&2
    return 1
  fi
}

download "$SUBSCRIBE_CLASH" "$CLASH_TMP" "Clash 订阅"
download "$SUBSCRIBE_V2RAY" "$V2RAY_TMP" "V2ray 订阅"

# Clash 配置至少应包含 proxies 段，否则视为异常返回
if ! grep -q 'proxies:' "$CLASH_TMP"; then
  echo "错误：Clash 订阅内容异常（缺少 proxies 段）" >&2
  exit 1
fi

# V2ray 订阅通常是 base64 编码的节点列表，解码后应能找到协议链接
if ! grep -qiE '(vmess|vless|trojan|ss|hysteria2?)://' "$V2RAY_TMP" \
  && ! base64 -d "$V2RAY_TMP" 2>/dev/null | grep -qiE '(vmess|vless|trojan|ss|hysteria2?)://'; then
  echo "错误：V2ray 订阅内容异常（未找到节点链接）" >&2
  exit 1
fi

# 校验通过后再替换正式文件，失败时保留上一次可用结果
mv "$CLASH_TMP" "$CLASH_FILE"
mv "$V2RAY_TMP" "$V2RAY_FILE"

echo "订阅更新成功："
ls -l "$CLASH_FILE" "$V2RAY_FILE"
echo "hope you have a good day~"
