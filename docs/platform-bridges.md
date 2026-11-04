# 平台桥实施文档（Host / mihon）

> **状态**：草案 / 待批准。**本文档批准前禁止在宿主合入新桥实现**（可继续维护既有 CF 通道与 JSVM 行为）。
>
> **姊妹文档（SDK）**：`D:\project\extension-sdk\docs\platform-bridges.md` 及 `docs/platform-bridges/*.md`。
>
> **既有接口说明**：[`plugin-interface.md`](./plugin-interface.md)（`$` DSL、wire、CF 质询重试）。
>
> **撰写时间**：2026-11-04（Asia/Shanghai）

## 1. 目标与边界

Host（本仓）为插件提供 **原生/系统能力**；SDK（`extension-sdk`）定义 **插件可见契约** 与 runtime shim。迁源硬依赖补齐时：

- 纯算法（AES-CTR、Zip 读、ECE、EXIF JPEG）→ **优先 SDK runtime**，Host 可不改。
- 系统能力（ArkWeb 可编程 WebView、字体/Canvas 叠字、可选 native 密码学、第二 JS 引擎）→ **Host 实现 + HostCalls/wire**，SDK 只挂 `$`。
- Cloudflare → **Host 统一**（已基本具备）；插件不开放求解器。

## 2. 与 SDK 的契约对齐

### 2.1 现有桥接层（核实）

| 机制 | 路径 | 用途 |
|------|------|------|
| `__nativeHostCall` / HostCalls | `entry/src/main/ets/jsvm/HostCalls.ets` | `cookie*`、`imageDecode`、`imageEncodePng` |
| HTTP | `NativeHttpBridge.ets` + `net/Http.ets` | 插件唯一网络出口；CF 判定；WebViewFetch 路由 |
| CF 质询 UI | `JsvmSource.ets` + AppStorage `CF_CHALLENGE_URL` | `CF_CHALLENGE:` → 弹层 → `cf_clearance` 重试一次 |
| 隐藏 ArkWeb 通道 | `net/WebViewFetch.ets` | CF 域页内 fetch（**非**插件 DSL） |
| 引擎 | `cpp/jsvm_engine.cpp` + Worker | 隔离 JSVM；PumpVm |
| shim | `resources/rawfile/plugin_runtime_jsvm.js`（由 `@honyomi/plugin-runtime` 构建） | `$` DSL |

### 2.2 命名约定（拟议新能力）

| SDK `$` | HostCalls `kind` 或 wire `type` | 备注 |
|---------|----------------------------------|------|
| `$.crypto.aesCtrDecrypt` | （无，runtime 内） | |
| `$.zip.list/read/readAt` | 可选 `zipList`/`zipRead` | 若选 Host 实现 |
| `$.webview.run` | wire `webviewRun`（需 UI 线程） | **不要**塞进同步 HostCalls 除非有阻塞桥 |
| `$.js.evaluate` | `jsEvaluate` | 隔离 Context |
| `$.image.readExif` | （无或 `imageReadExif`） | 推荐 runtime |
| `$.image.compositeOverlay` | `imageCompositeOverlay` | 需 drawing/字体 |
| `$.crypto.ecdhP256` / `eceDecrypt` | （无或 native） | 推荐 runtime |

### 2.3 版本协商

- 插件 `manifest.dslVersion` / `minAppVersion`：Host 拒绝过旧/过新（既有字段）。
- **拍板**：新桥是否捆绑一次 `dslVersion` 递增；是否增加运行期 `$.capabilities`（见 SDK 索引 §3）。

## 3. 分能力说明

### 3.1 AES-CTR

- **Host 职责**：方案选 runtime 时 **无**；若选 libohcrypto，新增 HostCall，注意 Worker 线程调用与密钥不清日志。
- **安全**：无额外权限；限制输入大小与现有 getBytes 一致（≤32MiB 量级）。
- **平台**：仅 Harmony 时与 runtime 方案等价可移植性差 — 更理由选 SDK 纯 JS。
- **细节**：见 SDK [`01-aes-ctr.md`](../../extension-sdk/docs/platform-bridges/01-aes-ctr.md)。

### 3.2 Zip / 解压

- **Host 职责**：本地 comic zip/cbz 已存在，**勿**与插件 ZipBridge 混用同一未审计路径。
- 若 Host 实现：在 C++/ArkTS 做 bomb 防护；经 HostCalls 返回 base64（与 image 一致）或后续 zero-copy ArrayBuffer。
- **AVIF**：`cpp/third_party/avif` 已存在 — 确认是否接入 `imageDecode`；接入后 `pt/randomscan` 图格式才闭环。
- **拍板点**：AVIF 是否已在 `HostCalls.decodeImage` 通路可用（需设备实测）。

### 3.3 WebView / runWebView

| 维度 | 要求 |
|------|------|
| 安全边界 | 仅 https/http；禁 file/hap；超时 destroy；全局并发 1（与 CF 弹层协调） |
| 权限 | 不提升应用权限；不暴露系统 Cookie 仓以外的 jar |
| 性能 | UI 线程 ArkWeb；Worker 等待 Promise；禁止插件嵌套多实例 |
| 与 WebViewFetch 关系 | Fetch = 透明 HTTP 通道；runWebView = 可编程会话。**共享** controller 池需仔细隔离，避免 CF 通道页被插件导航破坏 |
| Cookie | 默认双向同步 `CookieJar`；cf_clearance 绑定 UA 的既有策略保持 |
| 平台 | 当前仅 HarmonyOS ArkWeb；若未来桌面另栈，API 形状保持、实现分叉 |

**历史**：用户曾后置 WebView/CF；文档仍完整覆盖，阶段表标 P2。

### 3.4 Cloudflare

**已实现（保持并文档化）**：

1. `CfChallenge.isCfChallenge` 统一判定。
2. 错误前缀 `CF_CHALLENGE:` → 用户验证 WebView → 重试一次。
3. `WebViewFetch.markCfHost` → 后续请求走 ArkWeb fetch（JA3/指纹对齐）。

**Host 增强建议（可选，拍板）**：

- 对 DDoS-Guard 特征的弱检测（非 Turnstile）。
- 挑战失败时给插件稳定错误码（非 HTML 盾页正文）。
- **不**为 `scanmanga` 提供「关闭宿主 CF」开关（与统一策略冲突）。

插件契约见 SDK [`04-cloudflare.md`](../../extension-sdk/docs/platform-bridges/04-cloudflare.md)。

### 3.5 QuickJs / JS 求值

- 在 **新** JSVM_Env 或嵌入引擎中求值；**禁止**注入 `__nativeHostCall` / `$`。
- 超时、内存上限、禁网络。
- 体积：评估是否引入 QuickJS 源码进 `cpp/third_party`。
- 平台：随 so 分发；模拟器与真机同测。

### 3.6 ECDH / ECE

- 优先 SDK；Host 仅在产品要求「私钥不出 native」时介入。
- moetruyen 扩展 AEAD：单独安全评审，勿与 ECE 首版绑死。

### 3.7 Canvas / Typeface / TextOverlay

- HostCalls 走 `@ohos.graphics` / 字体管理；字体字节来自插件 HTTP（已经限流）再传入 — 校验 TTF 魔数与大小。
- 性能：叠字在 Worker 或后台任务；大图与 `imageDecode` 同等像素上限（现网 decode ≤1600 万像素）。
- 安全：SVG 解析器需防 XXE/实体膨胀（若用系统 SVG）；或只支持 runs 子集。

### 3.8 EXIF

- 推荐 SDK 纯 JS；Host 可不实现。
- 若 Host：只读标签白名单（至少 `ImageUniqueID`），禁止写回。

### 3.9 Next.js RSC

- **Host 无改动**。CF 挡读页时只走 §3.4。

## 4. 分阶段落地建议

> **最终以产品拍板为准。** 下表综合：用户历史（Next→DRM→Qwik；CTR 试过后缺桥；CF/WebView 后置）与 remaining 盘点 ROI。

| 阶段 | 建议项 | Host 工作量 | SDK 工作量 | 解锁（约） |
|------|--------|-------------|------------|------------|
| **P0** | AES-CTR + Zip 读成员 | 无或 AVIF 确认 | 大（crypto+zip+测） | `en/toonkotsu`、`pt/randomscan`（登录另议） |
| **P0′** | catalog Next util 继续加深 | 无 | 无（catalog） | 重 RSC 非 CF 项 |
| **P1** | CF 文档化 + 可选 challengeState；EXIF 只读；cryptoJsDecrypt 窄口 | 小 | 小–中 | viz；部分 DRM；受盾体验 |
| **P1–P2** | TextOverlay / renderText | 中 | 小 | `all/rawkumame` |
| **P2** | 可编程 WebView | **大** | 中 | WebView 8+、grouple/pam/libgroup、webnex… |
| **P2** | QuickJs 隔离求值 | 大 | 小 | mangago 等 |
| **P2** | ECDH+ECE（±AEAD） | 无或中 | 中 | nexus；moetruyen 另轨 |

**不要并行**：在缺批准时实现假 WebView/CTR；抢 catalog 半成品 CLAIM。

## 5. 每阶段验收（Host 视角）

1. **回归**：现有插件 CF 重试、WebViewFetch、image decode/encode、cookie 桥 e2e/设备冒烟不回退。
2. **shim 同步**：`plugin-runtime` 构建产物拷入 `rawfile/plugin_runtime_jsvm.js`（既有 `build.mjs --rawfile`）。
3. **安全清单**：新 HostCalls kind 写入 `HostCalls.ets` switch；默认拒绝未知 kind；参数 URL/字节校验。
4. **文档**：合入实现时同步改 `plugin-interface.md` §5.2 表，并去掉本文「批准前禁止」横幅。

## 6. 需袁学拍板的点（Host 相关）

1. P0 是否立即排期 CTR+Zip（SDK）及是否要求 Host 确认 AVIF。
2. WebView / CF 是否维持后置，还是上调 P1。
3. 可编程 WebView 与隐藏 WebViewFetch 是否共享单实例控制器。
4. 是否引入 `$.capabilities` 与 `dslVersion` 联动规则。
5. TextOverlay：全 SVG vs runs 子集。
6. moetruyen AEAD 族是否立项（包体积与合规）。

## 7. 交叉索引

| 文档 | 绝对路径 |
|------|----------|
| 本文 | `D:\project\mihon\docs\platform-bridges.md` |
| SDK 索引 | `D:\project\extension-sdk\docs\platform-bridges.md` |
| 插件接口 | `D:\project\mihon\docs\plugin-interface.md` |
| 执行摘要 | `D:\project\extension-source\.agent-reports\hard-bridge-impl-docs\RESULT.md` |