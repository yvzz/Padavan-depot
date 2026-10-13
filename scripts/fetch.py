#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
通用二进制同步脚本: 按 assets.conf 从 GitHub release(或任意直链)拉取文件,
输出到 out/ 并生成 index.json。

assets.conf 每行一条, 字段用 | 分隔:

    名称|源仓库|资产文件名|目标目录|[锁定版本]

    npc-yisier|yisier/nps|linux_mipsle_client.tar.gz|npc/yisier
    npc-djylb |djylb/nps |linux_mipsle_client.tar.gz|npc/djylb
    easytier  |EasyTier/EasyTier|easytier-linux-mipsel-v2.6.4.zip|easytier/mipsel

- 源仓库填 direct 时, "资产文件名" 位置改填完整直链, 文件名取 URL 末段,
  版本标记用内容 sha256 前 8 位(内容变了才会重新发布)。
- 第 5 字段填版本号可锁定版本(不跟随 latest)。
- 以 # 开头或空行为注释。

校验: .tar.gz/.tgz 用 tarfile 打开, .zip 用 zipfile 打开, 其它只做体积与
HTML 错误页检查 —— 防止把 404 页面当成二进制发布出去。
"""

import hashlib
import json
import os
import shutil
import sys
import tarfile
import time
import urllib.parse
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONF = os.path.join(ROOT, "assets.conf")
OUT = os.path.join(ROOT, "out")

TIMEOUT = 300


def http_headers():
    h = {
        "User-Agent": "Padavan-depot-sync",
        "Accept": "application/vnd.github+json",
    }
    token = os.environ.get("GH_TOKEN")
    if token:
        h["Authorization"] = "Bearer %s" % token
    return h


def http_get(url, timeout=60, accept=None):
    h = http_headers()
    if accept:
        h["Accept"] = accept
    req = urllib.request.Request(url, headers=h)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def read_conf():
    items = []
    with open(CONF, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = [p.strip() for p in line.split("|")]
            if len(parts) < 4:
                sys.exit("assets.conf 格式错误: %s" % line)
            items.append({
                "name": parts[0],
                "repo": parts[1],
                "asset": parts[2],
                "dest": parts[3],
                "tag": parts[4] if len(parts) > 4 and parts[4] else "",
            })
    return items


def find_asset(repo, asset, lock_tag=""):
    """返回 (tag, download_url, size); 找不到返回 None。"""
    if lock_tag:
        data = [json.loads(http_get(
            "https://api.github.com/repos/%s/releases/tags/%s" % (repo, lock_tag)))]
    else:
        data = json.loads(http_get(
            "https://api.github.com/repos/%s/releases?per_page=30" % repo))
    for rel in data:
        if rel.get("draft") or rel.get("prerelease"):
            continue
        for a in rel.get("assets", []):
            if a["name"] == asset:
                return rel["tag_name"], a["browser_download_url"], a["size"]
    if lock_tag:
        # 锁定版本但资产名不完全一致时, 允许按名字模糊匹配一次
        for rel in data:
            for a in rel.get("assets", []):
                if asset.lower() in a["name"].lower():
                    return rel["tag_name"], a["browser_download_url"], a["size"]
    return None


def download(url, path):
    req = urllib.request.Request(
        url, headers=dict(http_headers(), Accept="application/octet-stream"))
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r, open(path, "wb") as f:
        shutil.copyfileobj(r, f)


def verify(path):
    """确认下载的是真实文件而不是 HTML 错误页; 返回内容条目数。"""
    size = os.path.getsize(path)
    if size < 10 * 1024:
        raise RuntimeError("文件过小(%d 字节), 可能不是真实资产" % size)
    with open(path, "rb") as f:
        head = f.read(512)
    low = head[:200].lower()
    if b"<html" in low or b"<!doctype" in low:
        raise RuntimeError("下载到的是 HTML 页面, 不是二进制")

    name = os.path.basename(path).lower()
    if name.endswith((".tar.gz", ".tgz")):
        if head[:2] != b"\x1f\x8b":
            raise RuntimeError("不是 gzip 文件(魔数不符)")
        with tarfile.open(path, "r:gz") as tf:
            entries = tf.getnames()
    elif name.endswith(".zip"):
        if head[:2] != b"PK":
            raise RuntimeError("不是 zip 文件(魔数不符)")
        with zipfile.ZipFile(path) as zf:
            if zf.testzip() is not None:
                raise RuntimeError("zip 校验失败")
            entries = zf.namelist()
    else:
        entries = []
    if name.endswith((".tar.gz", ".tgz", ".zip")) and not entries:
        raise RuntimeError("压缩包内容为空")
    return entries


def sha256sum(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch_one(it):
    dstdir = os.path.join(OUT, it["dest"])
    os.makedirs(dstdir, exist_ok=True)

    if it["repo"] == "direct":
        url = it["asset"]
        filename = os.path.basename(urllib.parse.urlparse(url).path) or "download.bin"
        tag = ""
        source = url
    else:
        found = find_asset(it["repo"], it["asset"], it["tag"])
        if not found:
            print("    跳过: %s 未找到 %s" % (it["repo"], it["asset"]))
            return None
        tag, url, _remote_size = found
        filename = it["asset"]
        source = url
        print("    版本 %s" % tag)

    target = os.path.join(dstdir, filename)
    for attempt in range(3):
        try:
            download(url, target)
            break
        except Exception as e:
            print("    下载失败(第 %d 次): %s" % (attempt + 1, e))
            if attempt == 2:
                raise
            time.sleep(5)

    entries = verify(target)
    digest = sha256sum(target)
    if not tag:
        tag = "direct-%s" % digest[:8]

    with open(os.path.join(dstdir, "version.txt"), "w", encoding="utf-8") as f:
        f.write(tag + "\n")
    with open(os.path.join(dstdir, filename + ".sha256"), "w", encoding="utf-8") as f:
        f.write("%s  %s\n" % (digest, filename))

    print("    已下载 %.2f MB%s" % (
        os.path.getsize(target) / 1048576.0,
        (", 含 %d 个条目(如 %s)" % (len(entries), entries[:2])) if entries else ""))

    return {
        "name": it["name"],
        "repo": it["repo"],
        "tag": tag,
        "asset": filename,
        "path": "%s/%s" % (it["dest"], filename),
        "size": os.path.getsize(target),
        "sha256": digest,
        "source": source,
    }


def main():
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)

    result = []
    for it in read_conf():
        print("==> %s (%s)" % (it["name"], it["repo"]))
        try:
            r = fetch_one(it)
        except Exception as e:
            print("    失败: %s" % e)
            continue
        if r:
            result.append(r)

    if not result:
        sys.exit("没有任何资产被成功下载")

    index = {
        "updated": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "items": result,
    }
    with open(os.path.join(OUT, "index.json"), "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("\nindex.json 已生成, 共 %d 项" % len(result))


if __name__ == "__main__":
    main()
