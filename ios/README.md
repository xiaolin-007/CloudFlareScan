# CloudFlareScan for iOS

原生 iOS 移植（ObjC + WKWebView），产出可直接用 **TrollStore** 安装的 IPA。

界面与桌面版完全一致 —— 前端直接复用桌面版那份 Vue 构建产物，**JS 一行未改**；
后端（IP 生成 / TCP 延迟 / colo 探测 / 下载测速 / 导出）是 `ipgen.go`、`scanner.go`、
`speedtest.go`、`app.go`、`utils.go` 的逐函数 ObjC 复刻，CIDR 表与 IATA 表逐条照抄。

## 为什么不用 Wails

Wails v2 支持 Windows / macOS / Linux / Android，**没有 iOS 目标**。iOS 无法把 Go
二进制和 WebView 装进同一个 App 沙盒（App 只允许一个 `main` 可执行文件，且 JIT 受限）。
所以这里走的是 iOS 原生壳 + `WKWebView` 加载本地前端 + `WKScriptMessageHandler` 桥接，
在原前端与引擎之间补一层 `window.go` / `window.runtime` 垫片（`src/shim.js`），
使原版 dist 无需任何改动即可运行。

## 构建

依赖：

| 组件 | 说明 |
|---|---|
| clang + ld64.lld | 任意能编 Darwin arm64 的 clang 19+ |
| iPhoneOS SDK | 14.0 以上，含 `*.tbd`；Theos 的 `iPhoneOS16.5.sdk` 可用 |
| python3 | 生成 `index.html`、校验 IPA |

SDK 查找顺序：`$CFS_SDK` → `~/theos/sdks/iPhoneOS16.5.sdk` → `xcrun --sdk iphoneos --show-sdk-path`。

```sh
cd ios
./build.sh            # 产物 out/CloudFlareScan-iOS.ipa
./build.sh --debug    # 额外打开页面诊断探针（probe / CALL / CLICK 日志）
```

构建脚本做的事：生成 `res/www/index.html`（把 JS/CSS 内联进去）→ `clang` 交叉编译 →
组装 `Payload/CloudFlareScan.app` → 打 zip → 校验结构与 ad-hoc 签名 page hash。

> **为什么要内联 JS/CSS**：`WKWebView` 在 `file://` 下不加载 `<script src>` 子资源
> （标签存在但脚本从不执行，且资源错误不冒泡到 `window.onerror`）。
> 而原 Vite 产物用 `type="module"`（defer 语义），去掉 `module` 后变成立即执行，
> 此时 `<div id="app">` 尚未解析，Vue 的 `mount` 拿不到节点。因此内联脚本必须放在
> `<body>` 末尾（`defer` 对内联脚本无效）。

## 安装

TrollStore → 打开 IPA 安装即可。ad-hoc 签名由链接器写入（`-Wl,-adhoc_codesign`），
TrollStore 安装时会再重签并注入所需 entitlements。

## 使用

界面与桌面版一致。另有 URL scheme 便于快捷指令调用：

```
cfscan://scan?v=4&w=150&sample=1&port=443&th=1000
cfscan://scan?v=6&w=150&sample=100&port=443
cfscan://speed?n=10&port=443
cfscan://speed?n=10&port=443&region=SIN
cfscan://stop
```

| 参数 | 含义 | 默认 |
|---|---|---|
| `v` | 4 / 6 | 4 |
| `w` | 并发数 | 150 |
| `sample` | 每个 /24（v4）或每个段（v6）取样数 | 1 |
| `port` | 测试端口 | 443 |
| `th` | 延迟上限（ms），超过丢弃 | 1000 |
| `n` | 测速数量 | 10 |
| `region` | 地区码，如 `SIN` | 空＝完全测速 |

## 目录

```
ios/
├── build.sh                 编译 + 打包 + 校验
├── src/
│   ├── main.m               AppDelegate / UIWindow / WKWebView / URL scheme
│   ├── CSFBridge.{h,m}      WKScriptMessageHandler 桥；事件回推；导出与分享
│   ├── CSFEngine.{h,m}      扫描与测速引擎（BSD socket + Network.framework）
│   ├── CSFIPGen.{h,m}       Cloudflare CIDR 表与随机 IP 生成
│   ├── CSFExport.{h,m}      CSV（GB18030）/ CM 两种导出
│   ├── CSFLog.{h,m}         文件日志 Documents/cfs.log
│   └── shim.js              window.go / window.runtime 垫片（documentStart 注入）
├── res/
│   ├── Info.plist
│   ├── icon/                由桌面版 iconfile.icns 提取
│   └── www/                 前端产物（见下）
└── tools/
    ├── make_index.py        内联 JS/CSS 生成 index.html
    └── verify_ipa.py        包结构 + Mach-O + 签名 page hash 校验
```

## 关于 `res/www`

`assets/index-*.js`、`assets/index-*.css` 是桌面版的前端构建产物，未随源码提交；
本目录中的副本取自 **V5.0 release 的 macOS 二进制**（Wails 用 `go:embed` 把 dist
打进 Mach-O，可按 Go `embed` 的 `file{name,data,hash}` 表原样切出）。

如果上游后续更新了前端，替换 `res/www/assets/` 下同名文件后重新 `./build.sh` 即可。
若文件名（hash）改变，同步修改 `tools/make_index.py` 里的 `JS` / `CSS` 常量。

## 行为等价性

| 项目 | 桌面版 (Go) | 本移植 |
|---|---|---|
| IPv4 取样 | 每个 CIDR 拆 /24，每 /24 取 N 个，跳过网络地址 | 同 |
| IPv6 取样 | 每个 CIDR 取 N 个 | 同 |
| 延迟 | `net.DialTimeout` 1s | 非阻塞 `connect` + `poll` 1s |
| 延迟阈值 | `> threshold` 丢弃 | 同 |
| colo | TLS 优先、明文回退，`GET /cdn-cgi/trace` | 同（`Network.framework` + `SecTrust` 回调放行） |
| 测速 | `GET /__down?bytes=50000000`，3s 窗口 | 同 |
| 测速间隔 | 每个 IP 后 300ms | 同 |
| 排序 | 冒泡（延迟升序 / 速度降序） | 同（照抄，保证顺序一致） |
| CSV | GBK + CRLF + 8 列 | GB18030 + CRLF + 8 列 |
| CM | `ip:port#CODE 中文 (76ms  23MB/s)` | 同 |

## 已知限制

- **切后台会被挂起**：iOS 对普通 App 的后台网络任务只给约 30 秒
  （已申请 `beginBackgroundTask`），一次全量 IPv4 扫描约 95 秒，切走会被系统掐断。
- **延迟精度**：`connect()` 计时在 iOS 上约 1–2 ms 粒度，比桌面版略粗，数值会有轻微系统性偏高。
- 无 iPad 适配（`UIDeviceFamily` 仅 iPhone）。

## 实测

iPhone 15,2 / iOS 16.2 / TrollStore：

```
已生成 5957 个随机IPv4 IP          (并发 150)
扫描结束，共发现 57 个可用IP        (95 秒)
[1/50] 162.159.10.132   21.32 MB/s  新加坡
[2/50] 162.159.13.242   21.97 MB/s  新加坡
[3/50] 162.159.11.86    23.31 MB/s  新加坡
```
