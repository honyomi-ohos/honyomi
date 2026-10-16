# third_party/avif

Vendored AVIF decode stack used by `avif_decoder.cpp` (NAPI `avifDecodeToJpeg`).

| 组件 | 版本 | 来源 | 许可证 |
|---|---|---|---|
| libavif（git submodule） | v1.4.2 | https://github.com/AOMediaCodec/libavif | BSD（见 submodule 内 `LICENSE`） |
| libaom（git submodule，仅预编译静态库入库） | v3.15.2 | https://aomedia.googlesource.com/aom | BSD + AOM Patent License（见 `prebuilt/libaom-LICENSE`、`prebuilt/libaom-PATENTS`） |
| libyuv 桩 | - | `libyuv_stub.c` + `include/libyuv.h` | 本项目代码 |

获取全部源码：`git submodule update --init`（aom 需能访问 aomedia.googlesource.com）。

## prebuilt/ — libaom v3.15.2 预编译产物

只编解码器（`CONFIG_AV1_DECODER=1`、`CONFIG_AV1_ENCODER=0`），保留 8/10-bit 与动画支持。

- 源码由 git submodule 管理：`aom/`（锚定 v3.15.2，commit `af3dc9a`），
  获取：`git submodule update --init`（需能访问 aomedia.googlesource.com）
- 构建配置（双 ABI 一致）：
  - 工具链：DevEco Studio OHOS SDK `llvm/clang` + `build/cmake/ohos.toolchain.cmake`
  - `CMAKE_BUILD_TYPE=Release`，`CMAKE_C_FLAGS_RELEASE="-Oz -DNDEBUG -flax-vector-conversions=none"`
  - `CMAKE_ASM_FLAGS_RELEASE="-Oz -DNDEBUG"`（x86_64 汇编用 nasm 2.16.03）
- 当前产物（静态库经最终链接 --gc-sections 后进 HAP 的部分很小，arm64 约 590KB）：

| 文件 | 大小 | SHA256 |
|---|---|---|
| `prebuilt/arm64-v8a/libaom.a` | 3,201,172 | `86F1BAAEB90176EBFCDAE8A3D51A42C7E3D5316F5C8150F02EA7299E28ABB98E` |
| `prebuilt/x86_64/libaom.a` | 3,064,360 | `08C2F2781607CE3D297E0E9F27A1F9E1DD2B14FC1FBE4906F954C6EA8C3FBBA6` |

> 静态库内 ar 元数据不完全确定，重编产物 SHA256 可能微差（尺寸基本一致），属正常。

## 一键重编

```
build-aom.cmd / build-aom.sh    # 重编 arm64-v8a + x86_64，直接覆盖 prebuilt/ 下 libaom.a
build-aom.cmd arm64             # 仅 arm64-v8a
build-aom.sh x64                # 仅 x86_64
```

- Windows 用 `build-aom.cmd`；macOS / Linux（及 Git Bash）用 `build-aom.sh`，行为一致。
- SDK 通过华为约定的环境变量定位（无机器特定路径），按顺序：
  1. `OHOS_SDK` — 直接指向 native SDK 目录（含 `build/cmake/ohos.toolchain.cmake`）
  2. `DEVECO_SDK_HOME` — DevEco Studio SDK 根目录（含 `default/openharmony`）
  3. `OHOS_SDK_HOME` — 同 `DEVECO_SDK_HOME` 布局
  4. 默认安装位置兜底（Windows `%ProgramFiles%\Huawei\DevEco Studio\sdk`，macOS `/Applications/DevEco Studio.app/Contents/sdk`）
- 前置要求：DevEco Studio（含 OHOS SDK）、perl（macOS 自带；Windows 由 Git for Windows 提供）、
  x64 目标需要 nasm 在 PATH 上（macOS：`brew install nasm`；`.cmd` 会自动下载）。
- `.cmd` 通过无空格 junction 绕开 cmd.exe 的 cmake -D 引号问题；`.sh` 无需此 hack（bash 引号可靠），
  两者都会把 SDK 路径转成正斜杠（反斜杠会污染 `CMakeASMCompiler.cmake`）。
- 构建缓存在 `%TEMP%\mihon-aom`（`$TMPDIR/mihon-aom`），可随时删除。

重编后需重新构建 HAP 才会生效。
