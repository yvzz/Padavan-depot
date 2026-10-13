#!/usr/bin/env bash
# 把 out/ 里的内容发布到孤儿数据分支(默认 dist), 每次 force push 覆盖,
# 保证仓库体积恒定(不会每周累积一份 6MB 二进制)。
set -euo pipefail
cd "$(dirname "$0")/.."

BRANCH="${BRANCH:-dist}"
FORCE="${FORCE:-false}"

[ -d out ] || { echo "out/ 不存在, 先跑 scripts/fetch.py"; exit 1; }

# 本脚本会 checkout --orphan 并清空工作区, 结束后必须切回原来的分支,
# 否则后续步骤(同步 Gitee / 汇总)会找不到 scripts/ 与 out/。
ORIG="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
trap 'git checkout -q -f "$ORIG" >/dev/null 2>&1 || true' EXIT

git config user.name  "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

# 取远端分支上的旧索引用于比对
git fetch origin "$BRANCH" --depth=1 2>/dev/null || echo "远端还没有 $BRANCH 分支, 本次为首次发布"
: > /tmp/old_index.json
if git rev-parse --verify "origin/$BRANCH" >/dev/null 2>&1; then
	git show "origin/$BRANCH:index.json" > /tmp/old_index.json 2>/dev/null || : > /tmp/old_index.json
fi

new_tags="$(python3 -c "import json;print(' '.join(i['tag'] for i in json.load(open('out/index.json'))['items']))" 2>/dev/null || echo '')"
old_tags="$(python3 -c "import json;print(' '.join(i['tag'] for i in json.load(open('/tmp/old_index.json'))['items']))" 2>/dev/null || echo '')"

echo "新版本: ${new_tags:-无}"
echo "旧版本: ${old_tags:-无}"

if [ "$FORCE" != "true" ] && [ -n "$new_tags" ] && [ "$new_tags" = "$old_tags" ]; then
	echo "版本没有变化, 跳过推送(如需强制请在手动触发时勾选 force)"
	exit 0
fi

# 孤儿分支: 只保留 out/ 的内容, 不带 main 的 workflow/脚本。
# 注意 1: checkout --orphan 后要清空工作区, 所以先把 out/ 挪到临时目录, 否则会被一起删掉。
# 注意 2: 本地重复运行时本地 dist 分支已存在, --orphan 会失败, 先删掉本地同名分支。
#         (CI 每次都是新 runner 碰不到, 但本地跑第二次就会挂)
STAGE="$(mktemp -d)"
cp -r out/. "$STAGE"/

git branch -D "$BRANCH" >/dev/null 2>&1 || true
git checkout --orphan "$BRANCH" >/dev/null 2>&1
git rm -rf --cached . >/dev/null 2>&1 || true
find . -mindepth 1 -maxdepth 1 -not -name ".git" -exec rm -rf {} + 2>/dev/null || true
cp -r "$STAGE"/. .
rm -rf "$STAGE"
git add -A

# 孤儿分支首次提交时没有 HEAD, git diff --cached 会报错, 用 || true 兜住
if git diff --cached --quiet 2>/dev/null; then
	echo "内容无变化, 跳过提交"
	exit 0
fi

git commit -q -m "dist: ${new_tags:-更新} ($(date -u +%Y-%m-%d))"
git push -f origin "$BRANCH"
echo "已推送到 $BRANCH 分支"
