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
npc/yisier/linux_mipsle_client.tar.gz       yisier/nps → v0.26.x（默认）
npc/yisier/version.txt                      版本号
npc/yisier/linux_mipsle_client.tar.gz.sha256
npc/djylb/linux_mipsle_client.tar.gz        djylb/nps  → v0.34.x
npc/djylb/version.txt
npc/djylb/linux_mipsle_client.tar.gz.sha256
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

## 固件里怎么用

NPC 页面新增了「**自定义下载地址**」（固件提交 `9cc0e8cc7`），填入上面的完整直链即可：

```text
https://cdn.jsdelivr.net/gh/yvzz/Padavan-depot@dist/npc/yisier/linux_mipsle_client.tar.gz
```

填了之后 npc 就**只走这个地址**：不查 GitHub 版本、不做路径拼接、完全绕开 GitHub。
地址变了才会重新下载（版本标记用的就是地址本身）。

服务端是 0.26.x 就用 `npc/yisier/...`，是 0.34.x 就用 `npc/djylb/...`，**客户端与服务端版本必须匹配**。

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
