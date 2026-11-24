#!/bin/sh
# 推送 CPDazi-iOS 到 GitHub（Aoyt520）
# 依赖：环境变量 GITHUB_TOKEN（scopes: repo, workflow）
set -eu

REPO_NAME="${REPO_NAME:-CPDazi-iOS}"
OWNER="Aoyt520"
SRC="/var/minis/workspace/CPDazi-iOS"

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "错误：GITHUB_TOKEN 未设置"
  exit 1
fi

cd "$SRC"

# 1. 确认仓库是否已存在
echo "==> 检查 $OWNER/$REPO_NAME"
CODE=$(curl -s -o /tmp/repo.json -w '%{http_code}' -m 20 \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$OWNER/$REPO_NAME")

if [ "$CODE" = "404" ]; then
  echo "==> 仓库不存在，创建"
  CREATE=$(curl -s -o /tmp/create.json -w '%{http_code}' -m 25 \
    -X POST \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -d "{\"name\":\"$REPO_NAME\",\"description\":\"CP搭子 iOS 移植版 — 融合层协议与授权算法原生重写\",\"private\":false,\"has_issues\":true,\"has_wiki\":false}" \
    "https://api.github.com/user/repos")
  if [ "$CREATE" != "201" ]; then
    echo "创建失败 HTTP $CREATE"
    cat /tmp/create.json
    exit 1
  fi
  echo "==> 已创建"
elif [ "$CODE" = "200" ]; then
  echo "==> 仓库已存在，直接推送"
else
  echo "查询失败 HTTP $CODE"
  cat /tmp/repo.json
  exit 1
fi

# 2. 配置远程并推送（token 只出现在本次命令，不写入 .git/config）
echo "==> 推送"
git remote remove origin 2>/dev/null || true
git push "https://x-access-token:$GITHUB_TOKEN@github.com/$OWNER/$REPO_NAME.git" \
  HEAD:refs/heads/main --force

echo "==> 完成"
echo "仓库地址：https://github.com/$OWNER/$REPO_NAME"
