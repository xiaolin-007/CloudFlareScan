#!/usr/bin/env python3
"""把 assets/ 下的 JS 与 CSS 内联进 index.html。

必须内联：WKWebView 在 file:// 下不加载 <script src> 子资源（实测 scripts=1 但未执行），
而内联脚本必须放在 <body> 末尾 —— 原 Vite 产物用 type="module"（defer 语义），
去掉 module 后变立即执行，此时 #app 还不存在，Vue mount 会拿到 null。
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WWW = os.path.join(ROOT, "res", "www")
JS = os.path.join(WWW, "assets", "index-b48b5b2e.js")
CSS = os.path.join(WWW, "assets", "index-8c2ced60.css")

TEMPLATE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover, maximum-scale=1.0, user-scalable=no">
    <title>CloudFlare Scan</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        html, body {
            height: 100%;
            overflow: hidden;
            overscroll-behavior: none;
            -webkit-text-size-adjust: 100%;
            -webkit-tap-highlight-color: transparent;
            -webkit-touch-callout: none;
        }
        body {
            font-family: system-ui, -apple-system, 'Segoe UI', 'Microsoft YaHei', 'PingFang SC', 'Helvetica Neue', sans-serif;
            background: #F9FAFB;
        }
        #app {
            height: 100vh;
            padding-top: env(safe-area-inset-top, 0px);
            padding-bottom: env(safe-area-inset-bottom, 0px);
            box-sizing: border-box;
        }
        .app-container { height: 100% !important; }
        input, textarea, select { -webkit-user-select: text; user-select: text; }
    </style>
    <style>/* inlined css */
__CSS__
    </style>
</head>
<body>
    <div id="app"></div>
    <script>window.__cfs_bundle_ran = 1;</script>
    <script>/* inlined vue bundle */
__JS__
    </script>
</body>
</html>
"""


def main():
    for p in (JS, CSS):
        if not os.path.isfile(p):
            print("missing: %s" % p, file=sys.stderr)
            return 1

    js = open(JS, encoding="utf-8").read().replace("</script", "<\\/script")
    css = open(CSS, encoding="utf-8").read()

    html = TEMPLATE.replace("__JS__", js).replace("__CSS__", css)
    out = os.path.join(WWW, "index.html")
    open(out, "w", encoding="utf-8").write(html)
    print("index.html: %d bytes (js %d, css %d)" % (len(html), len(js), len(css)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
