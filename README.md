# Padavan-depot

Padavan 固件用的**二进制仓库站**。定时从各项目 GitHub release 拉取路由器用的二进制
（目前是 NPC 客户端），落到本仓库的 `dist` 分支，供固件开机时下载。

目的：上游 release 挂了 / GitHub 抽风 / 第三方加速站失效时，仍有自己可控的下载地址。

## 分支结构

| 分支 | 内容 | 说明 |
|---|---|---|
| `main` | 脚本、配置、文档 | 体积小，日常只改这里 |
| `dist` | 二进制文件 + `index.json` | **孤儿分支，每次 force push 覆盖**，体积恒定，不会每周累积 |

## 目录结构（`dist` 分支）

```text
index.json                                  所有包的版本/大小/sha256 汇总
npc/yisier/linux_mipsle_client.tar.gz       yisier/nps → v0.26.x
npc/yisier/version.txt                      版本号
npc/yisier/linux_mipsle_client.tar.gz.sha256
```

## 定时

每周一 **04:23（北京时间）** 自动跑一次（`cron: '23 20 * * 0'`，UTC）。
版本没变就跳过发布，不产生无谓的 commit。
也可以随时在 Actions 页面手动触发，勾选 `force` 可强制重发一次。

## 下载地址

`dist` 分支下的文件有三种取法，固件里填任意一个完整直链即可：

```text
# jsDelivr CDN（国内有节点，推荐）
https://cdn.jsdelivr.net/gh/yvzz/Padavan-depot@dist/npc/yisier/linux_mipsle_client.tar.gz
https://fastly.jsdelivr.net/gh/yvzz/Padavan-depot@dist/npc/yisier/linux_mipsle_client.tar.gz

# GitHub raw（直连，无 CDN）
https://raw.githubusercontent.com/yvzz/Padavan-depot/dist/npc/yisier/linux_mipsle_client.tar.gz
```

> jsDelivr 单文件上限 **20 MB**，超了会取不到；那种大文件走 raw 或自建服务器。
> jsDelivr 对分支内容有 CDN 缓存，新版本推送后最长约 12 小时才全网生效。

如果同步到了 Gitee（见下节），还多一个：

```text
https://gitee.com/你的用户名/Padavan-depot/raw/dist/npc/yisier/linux_mipsle_client.tar.gz
```

> Gitee 对**未登录访问 raw 文件**有限制，用之前必须先在路由器上实测能不能下到真文件（命令见下节第 5 步）。

## 同步到 Gitee（可选）

让每次同步后自动镜像一份到 Gitee，国内直连更快，也多一份备份。
**没配置会自动跳过**，不影响主流程 —— 不想用可以完全忽略这一节。

### 1. 在 Gitee 建一个空仓库

`https://gitee.com/projects/new` → 仓库名 `Padavan-depot` → **不要勾选**「初始化仓库 / 设置模板 / 添加 .gitignore」，保持完全空白，否则首次推送会被拒。

### 2. 生成 Gitee 私人令牌

Gitee → 右上角头像 → **设置** → 左侧「**私人令牌**」→ 生成新令牌 → 勾选 **`projects`**（读写项目）→ 复制令牌字符串（只显示一次）。

### 3. 在 GitHub 仓库里填 secrets

`https://github.com/yvzz/Padavan-depot/settings/secrets/actions` → **New repository secret**：

| Name | 值 |
|---|---|
| `GITEE_USER` | 你的 Gitee 用户名（空间地址，URL 里 `gitee.com/` 后面那段） |
| `GITEE_TOKEN` | 上一步的私人令牌 |

可选 repository **variables**（同名页面切到 Variables 标签）：

| Name | 默认 | 说明 |
|---|---|---|
| `GITEE_REPO` | `Padavan-depot` | 目标仓库名 |
| `MIRROR_HOST` | `gitee.com` | 换平台用，如 AtomGit 填 `atomgit.com` |

令牌里的特殊字符脚本会自动 URL 编码，不用自己处理。

### 4. 触发一次

Actions →「同步插件二进制」→ **Run workflow**。日志末尾出现「镜像同步完成」就成功了；若报「推送失败」，多半是仓库非空或令牌没勾 `projects` 权限。

之后每次定时同步都会自动带上镜像。推送只覆盖 `main` 和 `dist` 两个分支，不会删你在 Gitee 上的其它分支。

顺手在 Gitee 仓库「管理 → 仓库设置 → 默认分支」把默认分支改成 `main`（空仓库默认是 `master`，推过去之后 master 是空的）。

### 5. 务必先验证匿名能下载

Gitee 未登录访问 raw 文件可能被拦（返回登录页 HTML），**在路由器 ssh 上跑一次确认**：

```sh
curl -skL -o /tmp/npc.tgz -w "HTTP:%{http_code} 大小:%{size_download}\n" \
  https://gitee.com/你的用户名/Padavan-depot/raw/dist/npc/yisier/linux_mipsle_client.tar.gz
head -c 2 /tmp/npc.tgz | od -An -tx1     # 正常应是 1f 8b(gzip 魔数)
```

- 大小 ≈ 5.4MB 且魔数是 `1f 8b` → 可用，把该地址填进固件。
- 大小只有几 KB / 魔数不是 `1f 8b` → 被拦了，改回 jsDelivr 或 GitHub raw；或者把文件放到 Gitee 的**发行版附件**里（附件匿名可下载，但需要额外脚本，暂未实现）。

## 固件里怎么用

NPC 页面新增了「**自定义下载地址**」（固件提交 `9cc0e8cc7`），填入上面的完整直链即可：

```text
https://cdn.jsdelivr.net/gh/yvzz/Padavan-depot@dist/npc/yisier/linux_mipsle_client.tar.gz
```

填了之后 npc 就**只走这个地址**：不查 GitHub 版本、不做路径拼接、完全绕开 GitHub。
地址变了才会重新下载（版本标记用的就是地址本身）。

只保留 `npc/yisier/...`（yisier/nps，v0.26.x）。`djylb/nps`（v0.34.x）已移除——客户端必须与服务端版本匹配，实测 v0.34.x 客户端连不上 v0.26.x 的服务端。

## 加一个新包

改 `assets.conf`，按格式加一行就行，不用动脚本：

```text
# 名称|源仓库|资产文件名|目标目录|[锁定版本]
easytier|EasyTier/EasyTier|easytier-linux-mipsel-v2.6.4.zip|easytier/mipsel
```

- 源仓库填 `direct` 时，资产文件名位置改填**完整直链**，版本标记自动用内容 sha256 前 8 位（内容变了才重发）。
- 第 5 字段填版本号可锁定，不跟随 latest。
- 只会挑正式 release（跳过 draft / prerelease）里**存在该资产**的最新版本。

## 本地跑一次

```sh
python3 scripts/fetch.py     # 下载到 out/, 生成 index.json
BRANCH=dist FORCE=true bash scripts/publish.sh   # 发布到 dist 分支
```

下载后会自动校验：`.tar.gz` 用 tarfile 打开、`.zip` 用 zipfile 校验，
其余只做体积与 HTML 错误页检查 —— 防止把 404 页面当成二进制发布出去。
校验失败的包会被跳过，不影响其它包。
