# Honyomi 插件接口与能力文档

> 本文整理插件系统各层接口的边界与能力：宿主内部接口（`Source`）、插件作者面对的导出契约、
> 宿主注入插件的运行时 API（`$` DSL）、Worker 桥接 wire 协议，以及每项宿主行为
> （类型路由、能力开关、偏好持久化、质询重试等）分别由 manifest 声明还是运行期探测判定。

## 1. 架构分层与接口边界

```
UI / 服务层 (pages/*, DownloadService, PluginService)
    │  依赖宿主内部接口
    ▼
Source (source/Source.ets)                    ← 宿主内部接口（强类型 ArkTS）
    │  实现: JsvmSource (source/JsvmSource.ets) ← 宽松 JSON → 强类型模型归一化
    ▼
EngineGateway / EngineBackend (jsvm/EngineGateway.ets)   ← native-free 接缝
    │  实现: JsvmEngineBackend → JsvmExtensionManager (jsvm/JsvmExtensionManager.ets)
    ▼
JsvmWorker (worker 线程, JSON 消息)            ← wire 协议（§6）
    ▼
JSVM 引擎 (cpp/jsvm_engine.cpp, libjsvmengine.so)        ← 适配器层：探测导出、归一化方法名
    ▼
插件脚本 main.js                              ← 作者面契约（§4）
    （前置拼接 rawfile/plugin_runtime_jsvm.js 宿主运行时 shim，§5）
```

隔离模型：每个插件包 = 1 个专属 Worker + 1 个隔离 JSVM_Context。千级插件先以
"占位源"注册（仅 manifest 元数据），首次调用经 `engineStarter` 惰性拉起引擎；
引擎被 LRU 淘汰后再次调用自动重新拉起。

## 2. manifest.json — 安装期元数据

包级声明文件，引擎拉起之前即可用（占位源注册、浏览列表渲染都只依赖它）。

执行模型固定：所有插件一律 JSVM 引擎，宿主在 main.js 前无条件拼接共享运行时
（§5）；manifest 不需要（也不应）声明执行引擎或运行时字段。

| 字段 | 类型 | 能力 / 宿主行为 |
|---|---|---|
| `key` | string | 插件包唯一标识（多语言扩展共用一个包 key = `packageKey`） |
| `name` / `lang` | string | 源显示名 / 语言（浏览列表按语言分组） |
| `version` / `versionCode` | string / number | 升级比较与展示 |
| `baseUrl` | string | 源站根地址 |
| `nsfw` | boolean | NSFW 标记；关闭"显示 NSFW 源"时在浏览/搜索隐藏 |
| `supportsLatest` | boolean | **声明**支持最新页；实际支持 = 声明 ∧ 探测（§7） |
| `minAppVersion` | number | 宿主版本门槛 |
| `dslVersion` | number | DSL 契约版本 |
| `icon` | string | 包内图标文件名（缺省 UI 回退首字母） |
| `contentType` | string | `manga` \| `novel` \| `video`，缺省 `manga`；驱动宿主 UI 路由（§7） |
| `settings` | `RawManifestSetting[]` | **插件设置静态声明**（§2.1）：声明后设置页渲染与写入全部在宿主侧完成，无需拉起 JSVM 引擎 |

### 2.1 settings 数组 — 插件设置静态声明

每个元素声明一个设置行，宿主（`PluginService.declaredSettings`）在**不拉起引擎**的
前提下渲染设置页并直写持久化（`PluginService.setDeclaredPref`）：

| 字段 | 类型 | 说明 |
|---|---|---|
| `type` | string | `switch` \| `select` \| `edit` \| `password`（白名单外条目整条丢弃；`password` 渲染为 edit 行并强制敏感） |
| `key` | string | 偏好键（写入本插件扁平偏好存储（`$.prefs` 后端）的同名键） |
| `title` / `summary` | string | 行标题 / 说明 |
| `default` | string | 声明默认值（当前值 = 持久化值 ?? default） |
| `options` | `{value, label}[]` | `select` 选项 |
| `sensitive` | boolean | `true` 时值走 SecureStore（Asset Store）加密，不落明文 preferences |
| `hidden` | boolean | `true` 时不渲染（插件运行期自动写入的 token 等） |

已声明 `settings` 的插件无需（也应删除）运行期 `getSettingsSchema`；可保留
`setPreference` 作为引擎运行中的内存态同步钩子（宿主写入后 best-effort 转发，
引擎未运行时静默跳过，绝不为此拉起引擎）。未声明 `settings` 的插件仍走运行期
`getSettingsSchema` 回退路径（§4.2）。

## 3. Source — 宿主内部接口（`source/Source.ets`）

宿主 UI/服务层**只**依赖此接口；`LocalFsSource` / `LocalVideoSource` / `JsvmSource`
都实现它。

| 方法 | 能力 |
|---|---|
| `getPopularWorks(page)` | 热门列表（分页） |
| `getLatestWorks(page)` | 最新更新；`supportsLatest === false` 时宿主不调用 |
| `getSearchWorks(page, query)` | 搜索（分页） |
| `getWorkDetail(workKey)` | 作品详情 |
| `getChapterList(workKey)` | 章节列表 |
| `getPageList(chapterKey)` | 页图列表（`contentType === manga` 时调用） |
| `getChapterText(chapterKey)` | 小说正文；非小说源返回空串 |
| `getVideoList(chapterKey)` | 视频流列表（直链 / m3u8）；非视频源返回空数组 |
| `imageRequestHeaders()` | 图片加载附加头；`undefined` = 系统 Image 直连 |
| `key/name/lang/supportsLatest/contentType/nsfw/iconPath` | 元数据只读属性 |

## 4. 插件导出契约 — 作者面

### 4.1 导出形态（引擎启动时探测，`jsvm_engine.cpp`）

| kind | 导出位置 | 说明 |
|---|---|---|
| `simple` | `module.exports` 或 `globalThis.extension` | 宿主式 DSL 插件（`plugins/catalog/*`，TypeScript 经工具链构建） |

引擎按规范方法名直接绑定，不接受旧名或缩写别名。

### 4.2 宿主 → 插件方法表

| 方法 | 必选性 | 能力 | 参数 | 返回（宽松 JSON） |
|---|---|---|---|---|
| `getPopularWorks` | **必选** | 热门列表 | `(page)` | `{works: RawWork[], hasNextPage}` |
| `getSearchWorks` | **必选** | 搜索 | `(page, query)` | 同上 |
| `getWorkDetail` | **必选** | 作品详情 | `(workKey)` | `RawWork`（无 key/url 时宿主报 `plugin_invalid_detail`） |
| `getChapterList` | **必选** | 章节列表 | `(workKey)` | `RawChapter[]` |
| `getLatestWorks` | 可选 | 最新更新；导出后 `supportsLatest` 生效 | `(page)` | 同 popular |
| `getPageList` | manga **必选** | 页图列表 | `(chapterKey)` | `RawPage[]` |
| `getChapterText` | novel **必选** | 章节正文（纯文本/简单 HTML） | `(chapterKey)` | `string` 或 `{text\|content}` |
| `getVideoList` | video **必选** | 可播放流列表 | `(chapterKey)` | `RawVideo[]` |
| `getHeaders` | 可选 | 声明后图片经宿主 http 管线加载（Referer/Cookie），并做 Promise 并发去重预热 | `()` | `Record<string, string>` |
| `fetchImage` | 可选 | 图片字节由插件代取（反防盗链/解密图），宿主按 base64 解码 | `(pageUrl, imageUrl)` | base64 `string` |
| `getFilterList` | 可选 | 搜索过滤器声明（浏览页过滤面板） | `()` | `RawFilter[]` |
| `applyFilterState` | 可选 | 应用过滤面板状态 | `(stateJson)` | 任意 |
| `resetFilters` | 可选 | 重置过滤状态 | `()` | 任意 |
| `getSettingsSchema` | 可选（legacy） | 运行期设置 schema；**仅作 manifest 未声明 `settings` 时的回退**，查看/修改设置需拉起引擎 | `()` | `SourcePrefItem[]`（可包 JSON 字符串） |
| `setPreference` | 可选 | 引擎运行中的设置写入同步钩子：宿主直写持久化后 best-effort 转发，同步插件内存态；引擎未运行时静默跳过 | `(key, value)` | 任意 |

**未导出必需方法的行为**：`contentType === 'novel'` 缺 `getChapterText` →
`plugin_no_chapter_text`；`contentType === 'video'` 缺 `getVideoList` →
`plugin_no_video_list`（类型强校验，见 `JsvmSource.getChapterText/getVideoList`）。

### 4.3 返回模型（宽松字段 → 宿主模型，`JsvmSource.ets`）

| 模型 | 宽松字段 | 归一目标 |
|---|---|---|
| RawWork | `key\|url`, `title`, `coverUrl\|thumbnailUrl`, `author\|artist`, `description`, `genre` (string\|string[]), `status` (数字 1–6 \| 字符串) | `SManga` |
| RawChapter | `key\|url`, `name`, `chapterNumber`, `dateUpload`, `scanlator`, `pages`, `sortOrder`（缺省用数组下标） | `SChapter` |
| RawPage | `index`, `url`, `imageUrl`, `pageUrl` | `SPage` |
| RawVideo | `url`, `quality`（缺省序号）, `headers` | `SVideo`（`url` 为空丢弃） |
| SourcePrefItem | `type` `switch\|select\|edit`（`text`→`edit`，`password`→敏感 `edit`），`key`, `title`, `summary`, `value\|default\|defaultValue`, `options[{value,label}]` \| `values`+`titles`, `sensitive`, `hidden` | 设置页行；`sensitive: true` 值走 SecureStore（Asset Store）加密，不落明文 preferences |
| RawFilter | `type` `group\|tristate\|checkbox\|select\|sort`, `name`, `state`, `values`, `filters[]`（group 子项）, `index`（宿主回传前写入） | 过滤面板状态（`applyFilterState` 回传 JSON） |

## 5. 插件运行时注入 API — 宿主 → 脚本

### 5.1 引擎直接注入（`jsvm_engine.cpp`）

| API | 能力 |
|---|---|
| `console.log/warn/error` | 日志回收（hilog） |
| `fetchBytes` | 字节网络出口：经 Worker → `NativeHttpBridge` → ArkTS `Http` 管线（UA/CookieJar/重定向合并）。文本请求走 `$.http` |
| `querySelectorAll(html, cssQuery)` | lexbor 原生 CSS 选择器（支持 `:not`/`:has`） |

raw native 桥（`__nativeHttpRequest(Shared)` / `nativeSelector(Buffer)` /
`__nativeLog`）在 `BOOTSTRAP_JS` 内捕获进闭包后即从全局删除，不进插件可见面。

### 5.2 运行时 shim（rawfile/plugin_runtime_jsvm.js，前拼于 main.js）

**来源与构建**：源码在 `plugins/runtime/`（跟应用仓库走，不属于作者工具链）。
`cd plugins/runtime && npm run build` 写入 `dist/plugin_runtime_jsvm.js`，
`@honyomi/plugin-test` 通过包导出 `./shim` 加载它。只有宿主自动打包
（`entry` 模块任务 `GeneratePluginRuntime`，排在 `ProcessResource` 之前）才把同一构建写入
`entry/src/main/resources/rawfile/plugin_runtime_jsvm.js`。两处都不入库。
该任务使用正在执行 hvigor 的 Node。缺 `plugins/runtime/node_modules` 时，会先按 lockfile 执行 `npm ci`。
npm 依赖（对应许可证页条目）：

- `fast-text-encoding`（Apache-2.0）：TextEncoder/TextDecoder
- `whatwg-url` + `tr46` + `punycode`（MIT）：URL/URLSearchParams 规范实现
- `webidl-conversions`（BSD-2-Clause）：whatwg-url 依赖
- `js-md5`（MIT）：MD5
- `aes-js`（MIT）：AES-CBC
- `@noble/hashes`（MIT）：SHA-1/256/384/512、HMAC、PBKDF2
- `@noble/ciphers`（MIT）：AES-GCM

Polyfills：`atob`/`btoa`（手写宽松实现）、`TextEncoder`/`TextDecoder`、
`crypto.subtle`（AES-CBC / AES-GCM、SHA-1/256/384/512、HMAC、PBKDF2；
AES-CBC 的 pkcs7 解填充保持宽松，GCM 认证失败抛错）、
`crypto.getRandomValues`（宿主随机桥优先，缺失时整段回落 `Math.random`，
不可用于安全令牌）、`global`/`module`/`exports`。

`$` DSL（原 Mihon 命名空间）：

| API | 能力 |
|---|---|
| `$.http.get/post(url, ...)` | 同步式请求，返回 body；仅 `http://` / `https://` |
| `$.http.request(url, {method, headers, body})` | 返回 `{ok, status, headers, body, url}`；方法限 GET/HEAD/POST/PUT/PATCH/DELETE/OPTIONS，头禁止 CR/LF |
| `$.http.enqueue` | fire-and-forget |
| `$.http.getBytes(url, headers)` | 字节响应；桥未返回字节时抛错 |
| `$.html(html, baseUrl)` | 包装 DOM Document（选择器 + 相对链接解析） |
| `$.urlEncodeGbk(text)` | GBK URL 编码桥（`__nativeUrlEncodeGbk`） |
| `$.dns.set(host, ips)` | DNS 直连桥（`__nativeDnsSet`）：把域名钉到 1..8 个 IPv4（netstack 直连规则 + DoH 缓存 pin），绕过被污染的系统 DNS；host 须为域名（非 IP 字面量），失败抛错 |
| `$.crypto.base64Encode/Decode`、`aesCbcDecrypt`、`md5`、`md5Bytes`、`sha1/256/384/512`、`hmac`、`pbkdf2`、`aesGcmEncrypt/Decrypt` | 摘要/HMAC/派生/解密；PBKDF2 迭代上限 2_000_000，GCM nonce 固定 12 字节 |

### 5.3 插件偏好（prefs）

- 安全边界：每个引擎实例只承载一个扩展，偏好存储是该扩展自己的扁平映射
  （`k→v`），由 shim 持有为闭包私有对象；插件经 `$.prefs`（`createPrefs()`
  的后端）读写——raw 桥（`__PREFS_STORE__`/`__prefs_*`/`__prefsDump`）
  不进插件可见面，插件无法寻址、也无法读写其它插件的偏好；
- `$.prefs` 的键拒绝空串、NUL、`__proto__` / `constructor` / `prototype`；值必须是字符串。
  `dump()` / `all()` 返回字符串快照，不交出可写活引用；
- 宿主把该扩展的持久化快照作为 seed 注入脚本；
- 被标记 `prefsDirty` 的调用结束后，Worker dump 回 prefs JSON，宿主经
  `PluginPrefs` 去抖写入 preferences；敏感键（manifest `settings` 声明，或 legacy
  schema 声明）转 SecureStore；
- 推荐用 manifest `settings` 静态声明设置项（§2.1）：渲染与写入零引擎；
  插件脚本经 `createPrefs()` 读写即可，引擎恰在运行时宿主会把
  设置页写入经 `setPreference` 转发进来（参见 `plugins/catalog/emby/`）；
- 纵深防御（设备侧，`PluginService`/`PluginPrefs`）：安装拒绝 key 相同但
  `name` 不匹配的包（`plugin_key_conflict`），阻止仿冒既有插件 key 继承其
  持久化偏好；卸载清除明文 blob（`__extprefs:<key>`）与 SecureStore 敏感值，
  重装不继承旧值。安全回归见 `plugins/testing/test/security.test.ts`。

### 5.4 插件可见全局面（暴露面收敛）

- 插件可见全局收敛为：**标准 JS 内建 + 公开 DSL + CJS 约定**
  （`$`（含 `$.prefs`）/ `fetchBytes` / `querySelectorAll` /
  `crypto` / `URL` / `URLSearchParams` /
  `TextEncoder` / `TextDecoder` / `atob` / `btoa` / `console` / `module` /
  `exports` / `global`）；
- raw native 桥（`__nativeHttpRequest(Shared)` / `nativeSelector(Buffer)` /
  `__nativeLog` / `__nativeUrlEncodeGbk` / `__nativeRandomBytes` / `__nativeDnsSet`）由引擎用
  `OH_JSVM_SetNamedProperty` 装成普通可配置属性（不用 `CreateEnv` 的
  `JSVM_DEFAULT`：那是不可配置绑定，strict `delete` 会抛
  `Cannot delete property '…'`，插件安装直接失败）。bootstrap/shim 捕获进
  闭包后只删除可配置属性；裸 `fetch` 同样移除（HTTP 一律走 `$.http`/`fetchBytes`）；
- raw prefs 桥（`__PREFS_STORE__`/`__prefs_*`/`__prefsDump`）在 shim 初始化时
  捕获进闭包并从全局删除——偏好能力仅经 `$.prefs` 提供（§5.3）；
- shim 末尾按 `SURFACE_KEEP` 白名单兜底清理任何非公开契约的全局（含未来
  新增的桥）；`security.test.ts` 枚举 `globalThis` 自有属性锁定该面。

### 5.5 TypeScript 工具链（`plugins/`，`@honyomi/plugin-sdk`）

插件一律用 TypeScript 编写（支持完整 TS 语法，含 enum/namespace；Node 侧经
`tools/register.mjs` esbuild loader 直接运行 `.ts`），经工具链构建
（`plugins/README.md` 有完整流程）：

| 包 | 职责 |
|---|---|
| `@honyomi/plugin-sdk` | 作者面 API：`SourceExtension` 等契约类型、`defineExtension`、`createPrefs`、`workOf/chapterOf/pageOf/videoOf` 等模型助手、`$` DSL 全局类型声明 |
| `@honyomi/plugin-test` | 测试 harness：Node `vm` 沙箱逐字加载真实 shim + 构建产物 `main.js`，`loadExtension()` 返回 `{ext, calls, prefs}`；`createFixtureFetch()` 按 `fixtures/index.json`（精确 URL 或 `/正则/`）回放本地文件 |
| `@honyomi/plugin-tools` | CLI：`build [key...]`（esbuild 编译压缩全部插件为单文件 iife → `dist/catalog/<key>/main.js`，与源码分离）/ `publish` / `check` / `serve [dir] [--host 127.0.0.1\|0.0.0.0]`（缺省监听 0.0.0.0）；`register.mjs` 为 Node 提供 TS loader（enum 等完整语法直跑 `.ts`） |

约定：全部插件的 `.ts` 源文件是唯一真源，构建产物 `dist/` 不入库
（`.gitignore` 排除）；插件可拆分多个源文件（入口固定 `main.ts`，如
`plugins/catalog/picacomic/sha256.ts`）；自手写 JS 迁移的插件逻辑与原版 1:1。
每个插件自带 `test/<key>.test.ts`（`npm test` 全量回归）。典型入口：

```ts
import { createPrefs, defineExtension } from '@honyomi/plugin-sdk';
import type { SourceExtension } from '@honyomi/plugin-sdk';

const prefs = createPrefs();                       // 本扩展的扁平偏好存储
const ext: SourceExtension = { /* getPopularWorks / getSearchWorks / ... */ };
defineExtension(ext);                            // 写宿主 module.exports
```

迁移示范见 `plugins/catalog/`（全部 31 个插件：main.ts + test/<key>.test.ts）。


## 6. Wire 协议（JsvmExtensionManager ↔ JsvmWorker）

全部为 JSON 字符串消息；调用结果 envelope：`{ok: true, data}` 或 `{ok: false, error}`。

| 方向 | 消息 | 说明 |
|---|---|---|
| 宿主→Worker | `{"type":"init","code": seed+code}` | seed = 偏好回灌 prologue |
| Worker→宿主 | `{"type":"ready","ok","kind","prefs"}` | kind = `simple` |
| 宿主→Worker | `{"type":"call","seq","name","argsJson","prefsDirty"}` | `prefsDirty` = 方法名含 `pref`/`filter`（§7） |
| Worker→宿主 | `{"type":"result","seq","ok","json","mem","prefs"}` | `mem` = JS 堆用量上报（看门狗） |
| 宿主→Worker | `{"type":"destroy"}` → `{"type":"destroyed"}` | Worker 自退，3s terminate 安全网 |

保留方法名（不经适配器，`__honyomiCall` 内特判）：

| 名称 | 能力 |
|---|---|
| `__kind` | 返回适配器 kind |
| `__methods` | 枚举实际导出方法（能力探测的依据，§7） |
| `__prefsDump` | dump 偏好快照（适配器特判，改查 `$.prefs.dump()`） |
| `__xxx`（脚本自注册的全局函数） | 逃逸口：无适配器也可调用 |

错误与质询：envelope `error` 以 `CF_CHALLENGE:` 前缀上抛 → 宿主转
`WebChallengeError` → 打开单实例验证 webview → 轮询 `cfVerifiedTick`（上限 2 分钟）
→ 通过后携新 `cf_clearance` **重试一次**，放弃则原样上抛（`JsvmSource.call`）。

资源限制：JS 堆预算 2MB/插件；存活引擎上限 12（LRU 淘汰，加载中/活跃引擎不淘汰）；
READY 超时 30s；调用超时 190s（> native 180s pump 上限），超时判 broken 并强杀 Worker。

## 7. 宿主定制行为的判定来源（manifest 声明 vs 运行期探测）

原则：**manifest 声明"宿主该渲染/路由什么"（安装期、占位源可用）；
`__methods` 探测验证"脚本实际能做什么"（引擎加载期、自校验、不可谎报）。**

| 宿主行为 | 判定来源 | 位置 |
|---|---|---|
| 详情页路由（MangaDetail / NovelReader / VideoPlayer）、入库分类 | manifest `contentType` | `ContentType.normalize` |
| NSFW 浏览/搜索隐藏 | manifest `nsfw` | 浏览/搜索过滤 |
| `supportsLatest` | **混合**：manifest 声明 ∧ `__methods` 含 `getLatestWorks` | `JsvmSource` 构造器 / `upgrade` |
| 最新页缺方法回退热门 | `__methods` 探测 | `getLatestWorks` |
| 图片走宿主管线（带 Referer/Cookie） | `__methods` 含 `getHeaders`（warm 缓存 + 并发去重） | `warmImageHeaders` |
| 图片由插件代取（base64） | `__methods` 含 `fetchImage` | `fetchPageImage` |
| 设置页是否可配置 | **混合**：manifest `settings` 声明优先（零引擎），空则回退 `__methods` 含 `getSettingsSchema` | `ExtensionDetailPage.loadSchema` / `isConfigurable` |
| 设置页写入路径 | manifest `settings` → 宿主直写 `PluginPrefs` + best-effort `setPreference` 转发；legacy → 引擎调用 `setPreference` | `PluginService.setDeclaredPref` / `ExtensionDetailPage.applyPref` |
| 搜索过滤面板 | `__methods` 含 `getFilterList` / `applyFilterState` / `resetFilters` | `getFilterList` 等 |
| 小说/视频缺方法强报错 | manifest `contentType` ∧ `__methods` | `getChapterText` / `getVideoList` |
| 调用后 dump prefs（`prefsDirty`） | 方法名启发式（含 `pref`/`filter`）——可迁移为 manifest 声明，收益低 | `prefsWritingMethod` |
| Cloudflare 质询重试 | envelope 错误前缀，全方法统一包装 | `JsvmSource.call` |

为何不能全部搬进 manifest：

1. **占位源**：千级插件只注册元数据、不拉引擎，安装期唯一可用信息就是 manifest
   ——这部分已经走 manifest（contentType/nsfw/name 等）；
2. **可信度**：manifest 是作者声明、可能失真或过期；`__methods` 是对实际适配器对象
   枚举出来的（`jsvm_engine.cpp` `__honyomiCall('__methods')`），自校验、不可谎报。

## 8. 相关文件索引

| 关注点 | 文件 |
|---|---|
| 宿主源接口 + 注册表 | `entry/src/main/ets/source/Source.ets` |
| JSVM 源适配（归一化/探测/质询重试） | `entry/src/main/ets/source/JsvmSource.ets` |
| 引擎接缝（native-free 接口） | `entry/src/main/ets/jsvm/EngineGateway.ets` / `JsvmEngineBackend.ets` |
| Worker 管线 / wire 协议 / LRU | `entry/src/main/ets/jsvm/JsvmExtensionManager.ets` |
| HTTP 桥（插件唯一网络出口） | `entry/src/main/ets/jsvm/NativeHttpBridge.ets` |
| 偏好持久化（明文 + SecureStore） | `entry/src/main/ets/jsvm/PluginPrefs.ets` |
| 引擎适配器（导出探测/方法归一/保留名） | `entry/src/main/cpp/jsvm_engine.cpp` |
| 宿主运行时 shim（polyfills + `$` DSL） | `entry/src/main/resources/rawfile/plugin_runtime_jsvm.js` |
| 插件 TS 工具链（SDK/测试/构建发布） | `plugins/`（`sdk/` `testing/` `tools/`，见 `plugins/README.md`） |
| 插件样例（video/manga/novel） | `plugins/catalog/*` |
