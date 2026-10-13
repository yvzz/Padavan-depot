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

# checkout 默认只拉当前分支, 这里把所有分支都取回来
git fetch origin '+refs/heads/*:refs/remotes/origin/*' --depth=1 2>/dev/null || true

for b in $BRANCHES; do
	if git rev-parse --verify "origin/$b" >/dev/null 2>&1; then
		echo "==> 推送 $b → ${HOST}/${USER}/${REPO}"
		if ! git push -f "$REMOTE_URL" "refs/remotes/origin/$b:refs/heads/$b"; then
			echo "推送失败: 请先在 https://${HOST}/${USER}/${REPO} 建一个空仓库(不要勾选初始化), 并确认令牌有 projects 写权限"
			exit 1
		fi
	else
		echo "==> origin/$b 不存在, 跳过"
	fi
done

echo "镜像同步完成"
