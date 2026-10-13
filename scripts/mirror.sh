#!/usr/bin/env bash
# 把已发布的分支镜像推送到 Gitee(或任意其它 Git 托管)。
#
# 未配置 GITEE_USER / GITEE_TOKEN 时直接跳过, 不影响主流程 ——
# 所以你可以先不配置, 想用的时候再加 secrets。
#
# 环境变量:
#   GITEE_USER       Gitee 用户名(空间地址)          必填
#   GITEE_TOKEN      Gitee 私人令牌(需 projects 权限) 必填
#   GITEE_REPO       目标仓库名, 默认 Padavan-depot
#   MIRROR_BRANCHES  要推送的分支, 默认 "main dist"
#   MIRROR_HOST      托管域名, 默认 gitee.com (换 AtomGit 等可填 atomgit.com)
set -euo pipefail
cd "$(dirname "$0")/.."

USER="${GITEE_USER:-}"
TOKEN="${GITEE_TOKEN:-}"
REPO="${GITEE_REPO:-Padavan-depot}"
BRANCHES="${MIRROR_BRANCHES:-main dist}"
HOST="${MIRROR_HOST:-gitee.com}"

if [ -z "$USER" ] || [ -z "$TOKEN" ]; then
	echo "未配置 GITEE_USER / GITEE_TOKEN, 跳过镜像同步"
	exit 0
fi

# 令牌里可能有特殊字符, 必须 URL 编码后再拼进 URL
ENC="$(python3 -c "import urllib.parse,os;print(urllib.parse.quote(os.environ['GITEE_TOKEN'],safe=''))")"
REMOTE_URL="https://${USER}:${ENC}@${HOST}/${USER}/${REPO}.git"

# 防御: 若上一步 publish.sh 之后工作区还停在 dist 分支(已被清空), 先切回主分支,
# 否则 git fetch / push 虽能跑, 但工作区状态与预期不一致。
if [ ! -d scripts ]; then
	echo "工作区不在主分支, 切回 ${MAIN_BRANCH:-main}"
	git checkout -q -f "${MAIN_BRANCH:-main}" 2>/dev/null || true
fi

# checkout 默认只拉当前分支, 这里把全部分支取回来。
# 必须完整拉取(不能 --depth): 浅克隆推到 Gitee 会被拒 "shallow update not allowed"。
# 不再吞掉错误输出 —— 之前 2>/dev/null 导致 dist 拉不到时静默跳过, 查了半天。
git fetch --unshallow origin 2>&1 | sed 's/^/  fetch: /' || true
git fetch origin '+refs/heads/*:refs/remotes/origin/*' 2>&1 | sed 's/^/  fetch: /' || true
echo "本地已跟踪的远端分支: $(git branch -r | tr -d ' ' | tr '\n' ' ')"
echo "本地分支: $(git branch | tr -d '*' | tr -d ' ' | tr '\n' ' ')"

for b in $BRANCHES; do
	# 优先用远端跟踪 ref; 拿不到就退回本地分支
	# (publish.sh 刚在本地建过 dist, 此时 origin/dist 可能还没同步到)
	if git rev-parse --verify "origin/$b" >/dev/null 2>&1; then
		REF="refs/remotes/origin/$b"
	elif git rev-parse --verify "refs/heads/$b" >/dev/null 2>&1; then
		echo "  (origin/$b 不存在, 改用本地分支 $b)"
		REF="refs/heads/$b"
	else
		echo "==> $b 既没有 origin/$b 也没有本地分支, 跳过"
		continue
	fi

	echo "==> 推送 $b ($REF) → ${HOST}/${USER}/${REPO}"
	if ! git push -f "$REMOTE_URL" "$REF:refs/heads/$b"; then
		echo "推送失败: 确认 https://${HOST}/${USER}/${REPO} 是空仓库(没勾选初始化)、令牌勾了 projects 写权限"
		echo "若报 shallow update not allowed, 说明是浅克隆 —— 检查 workflow 里 checkout 的 fetch-depth 是否为 0"
		exit 1
	fi
done

echo "镜像同步完成"
echo "远端分支: $(git ls-remote --heads "$REMOTE_URL" 2>/dev/null | sed 's#.*refs/heads/##' | tr '\n' ' ')"
