#!/bin/sh
# CP搭子 iOS 构建盯梢 —— 每次调用输出一行摘要，供 minis-scheduled 汇总
# 依赖：GITHUB_TOKEN 环境变量
set -u

OWNER="Aoyt520"
REPO="CPDazi-iOS"
API="https://api.github.com/repos/$OWNER/$REPO"
OUT="/var/minis/workspace/CPDazi-iOS/build-watch"
mkdir -p "$OUT"

if [ -z "${GITHUB_TOKEN:-}" ]; then
  TOKF="/var/minis/workspace/CPDazi-iOS/.token"
  if [ -f "$TOKF" ]; then
    GITHUB_TOKEN=$(cat "$TOKF")
    export GITHUB_TOKEN
  fi
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "STATUS=NO_TOKEN"
  echo "需要设置 GITHUB_TOKEN 环境变量"
  exit 0
fi

gh() {
  # gh <url> [extra curl args...]
  url="$1"
  shift
  curl -s -m 30 -H "Authorization: Bearer $GITHUB_TOKEN" \
       -H "Accept: application/vnd.github+json" "$@" "$url"
}

RUN=$(gh "$API/actions/runs?per_page=1")

RID=$(echo "$RUN" | python3 -c "import sys,json
d=json.load(sys.stdin); r=(d.get('workflow_runs') or [{}])[0]
print(r.get('id',''))" 2>/dev/null)

if [ -z "$RID" ]; then
  echo "STATUS=API_FAIL"
  echo "$RUN" | head -3
  exit 0
fi

INFO=$(echo "$RUN" | python3 -c "
import sys,json
d=json.load(sys.stdin); r=(d.get('workflow_runs') or [{}])[0]
print(r.get('status',''), '|', r.get('conclusion') or '-', '|', (r.get('head_sha') or '')[:7], '|', r.get('created_at',''))
" 2>/dev/null)
echo "RUN=$RID"
echo "INFO=$INFO"

STATUS=$(echo "$INFO" | cut -d'|' -f1 | tr -d ' ')
CONCL=$(echo "$INFO" | cut -d'|' -f2 | tr -d ' ')
CRT=$(echo "$INFO" | cut -d'|' -f4 | tr -d ' ')

echo "STATUS=$STATUS CONCL=$CONCL"

if [ "$STATUS" = "queued" ]; then
  python3 - "$CRT" <<'PY'
import sys, datetime
try:
    t = datetime.datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
    m = int((datetime.datetime.now(datetime.timezone.utc) - t).total_seconds() / 60)
    print(f"排队中，已等 {m} 分钟（{m//60}h{m%60}m）")
except Exception:
    print("排队中")
PY

elif [ "$STATUS" = "in_progress" ]; then
  echo "构建进行中，正在编译"

elif [ "$STATUS" = "completed" ]; then
  if [ "$CONCL" = "success" ]; then
    echo "构建成功，下载 artifact"
    ART=$(gh "$API/actions/runs/$RID/artifacts")
    AURL=$(echo "$ART" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for a in d.get('artifacts',[]):
    if not a.get('expired'):
        print(a.get('archive_download_url','')); break
" 2>/dev/null)
    if [ -n "$AURL" ]; then
      ZIP="$OUT/CPDAzi-unsigned-ipa.zip"
      curl -sL -m 240 -H "Authorization: Bearer $GITHUB_TOKEN" \
           -H "Accept: application/vnd.github+json" -o "$ZIP" "$AURL"
      SZ=$(wc -c < "$ZIP" 2>/dev/null || echo 0)
      echo "下载：$ZIP (${SZ}B)"
      if [ "$SZ" -gt 10000 ]; then
        rm -rf "$OUT/unzipped" && mkdir -p "$OUT/unzipped"
        unzip -o -q "$ZIP" -d "$OUT/unzipped" 2>/dev/null
        IPA=$(find "$OUT/unzipped" -name '*.ipa' | head -1)
        if [ -n "$IPA" ]; then
          cp "$IPA" "$OUT/CPDAzi.ipa"
          echo "IPA_READY=$OUT/CPDAzi.ipa"
          ls -lh "$OUT/CPDAzi.ipa"
        else
          echo "包内无 .ipa，内容："
          find "$OUT/unzipped" -type f | head -10
        fi
      fi
    else
      echo "artifact 未找到或已过期"
    fi
  else
    echo "构建失败：$CONCL"
    echo "日志：https://github.com/$OWNER/$REPO/actions/runs/$RID"
    JOBS=$(gh "$API/actions/runs/$RID/jobs")
    echo "$JOBS" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for j in d.get('jobs',[]):
    for s in j.get('steps',[]):
        if s.get('conclusion')=='failure':
            print('失败步骤:', s.get('name'))
" 2>/dev/null
  fi
else
  echo "状态：$STATUS"
fi
