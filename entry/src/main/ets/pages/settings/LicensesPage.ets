// 开源许可证页（对齐 Mihon OpenSourceLicensesScreen / aboutlibraries 详情 sheet）：
// 项目依赖/内置三方库清单，点击条目弹出详情 sheet，
// 协议全文随包打包在 rawfile（license_*.txt）中直接应用内展示，不跳转网页
import { ThemePalette } from '../../common/Theme';
import { SheetPreset } from '../components/SheetPreset';
import { Util } from '../../common/Util';
import { NavGlassPage } from '../../common/HdsNavHost';
import { AppIcon } from '../components/AppIcon';

// 开源组件条目：名称 / 版本 / 协议 / 主页 / 协议全文 rawfile / 用途说明（说明走资源本地化）
interface LicenseItem {
  name: string;
  version: string;
  license: string;
  url: string;
  licenseFile: string;
  description: ResourceStr;
}

// 项目实际使用的开源组件清单（含参考架构、图标资源、平台 SDK 与三方库）；
// licenseFile 指向 resources/rawfile 下随包的协议全文
function buildLicenseItems(): LicenseItem[] {
  const items: LicenseItem[] = [
    {
      name: 'Mihon / Tachiyomi',
      version: '',
      license: 'Apache-2.0',
      url: 'https://github.com/mihonapp/mihon',
      licenseFile: 'license_apache2.txt',
      description: $r('app.string.licenses_desc_mihon')
    },
    {
      name: 'Material Symbols',
      version: '',
      license: 'Apache-2.0',
      url: 'https://github.com/google/material-design-icons',
      licenseFile: 'license_apache2.txt',
      description: $r('app.string.licenses_desc_material')
    },
    {
      name: 'OpenHarmony',
      version: '',
      license: 'Apache-2.0',
      url: 'https://gitee.com/openharmony',
      licenseFile: 'license_apache2.txt',
      description: $r('app.string.licenses_desc_openharmony')
    },
    {
      name: 'libavif',
      version: '1.4.2',
      license: 'BSD-2-Clause',
      url: 'https://github.com/AOMediaCodec/libavif',
      licenseFile: 'license_libavif.txt',
      description: $r('app.string.licenses_desc_libavif')
    },
    {
      name: 'libaom',
      version: '3.15.2',
      license: 'BSD-2-Clause + AOM Patent License',
      url: 'https://aomedia.googlesource.com/aom/',
      licenseFile: 'license_libaom.txt',
      description: $r('app.string.licenses_desc_libaom')
    },
    {
      name: 'Lexbor',
      version: '1.9.0',
      license: 'Apache-2.0',
      url: 'https://github.com/lexbor/lexbor',
      licenseFile: 'license_apache2.txt',
      description: $r('app.string.licenses_desc_lexbor')
    },
    {
      name: '@ohos/video-cache',
      version: '1.0.9',
      license: 'Apache-2.0',
      url: 'https://gitcode.com/openharmony-tpc/openharmony_tpc_samples/tree/master/OhosVideoCache',
      licenseFile: 'license_apache2.txt',
      description: $r('app.string.licenses_desc_videocache')
    },
    {
      // 插件运行时由 @honyomi/plugin-runtime 经 esbuild 在宿主构建时生成（不入库），
      // 以下为其 npm 依赖；版本以 extension-sdk/packages/runtime/package.json 为准
      name: 'whatwg-url',
      version: '14.2.0',
      license: 'MIT',
      url: 'https://github.com/jsdom/whatwg-url',
      licenseFile: 'license_mit.txt',
      description: $r('app.string.licenses_desc_whatwgurl')
    },
    {
      name: 'fast-text-encoding',
      version: '1.0.6',
      license: 'Apache-2.0',
      url: 'https://github.com/samthor/fast-text-encoding',
      licenseFile: 'license_apache2.txt',
      description: $r('app.string.licenses_desc_fasttextencoding')
    },
    {
      name: 'webidl-conversions',
      version: '7.0.0',
      license: 'BSD-2-Clause',
      url: 'https://github.com/jsdom/webidl-conversions',
      licenseFile: 'license_webidl.txt',
      description: $r('app.string.licenses_desc_webidlconversions')
    },
    {
      name: 'js-md5',
      version: '0.8.3',
      license: 'MIT',
      url: 'https://github.com/emn178/js-md5',
      licenseFile: 'license_mit.txt',
      description: $r('app.string.licenses_desc_jsmd5')
    },
    {
      name: '@noble/hashes',
      version: '2.4.0',
      license: 'MIT',
      url: 'https://github.com/paulmillr/noble-hashes',
      licenseFile: 'license_mit.txt',
      description: $r('app.string.licenses_desc_noblehashes')
    },
    {
      name: '@noble/ciphers',
      version: '2.4.0',
      license: 'MIT',
      url: 'https://github.com/paulmillr/noble-ciphers',
      licenseFile: 'license_mit.txt',
      description: $r('app.string.licenses_desc_nobleciphers')
    },
    {
      name: 'aes-js',
      version: '3.1.2',
      license: 'MIT',
      url: 'https://github.com/ricmoo/aes-js',
      licenseFile: 'license_mit.txt',
      description: $r('app.string.licenses_desc_aesjs')
    },
    {
      // torrent 模块（@honyomi/torrent）内置的 BT 下载引擎及其依赖，
      // 预编译静态库随包分发，协议全文取自模块 prebuilt 目录
      name: 'libtorrent-rasterbar',
      version: '2.0.15',
      license: 'BSD-3-Clause',
      url: 'https://github.com/arvidn/libtorrent',
      licenseFile: 'license_libtorrent.txt',
      description: $r('app.string.licenses_desc_libtorrent')
    },
    {
      name: 'OpenSSL',
      version: '3.5.9',
      license: 'Apache-2.0',
      url: 'https://github.com/openssl/openssl',
      licenseFile: 'license_openssl.txt',
      description: $r('app.string.licenses_desc_openssl')
    },
    {
      name: 'Boost',
      version: '1.86.0',
      license: 'BSL-1.0',
      url: 'https://www.boost.org/',
      licenseFile: 'license_boost.txt',
      description: $r('app.string.licenses_desc_boost')
    }
  ];
  return items;
}

// 许可证条目行（对齐 mihon aboutlibraries 列表项）：两行布局，
// 首行库名，次行「v版本 · 协议」，小屏下换行展示不截断
@Component
struct LicenseRow {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State hovered: boolean = false;
  name: string = '';
  sub: string = '';
  onTap: () => void = () => {
  };

  build() {
    Row() {
      Column() {
        Text(this.name)
          .fontSize(16)
          .fontColor(this.pal.text)
          .maxLines(1)
          .width('100%')
        Text(this.sub)
          .fontSize(13)
          .fontColor(this.pal.sub)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      AppIcon({ name: 'keyboard_arrow_right', iconSize: 20 })
        .margin({ left: 4 })
    }
    .width('100%')
    .constraintSize({ minHeight: 52 })
    .padding({
      left: 16,
      right: 12,
      top: 8,
      bottom: 8
    })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.hovered ? this.pal.chip : Color.Transparent)
    .onClick(() => this.onTap())
    .onHover((isHover: boolean) => {
      this.hovered = isHover;
    })
  }
}

@Component
export struct LicensesPage {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('windowW') windowW: number = 0;
  @State items: LicenseItem[] = [];
  @State showDetail: boolean = false;
  @State selectedIndex: number = -1;
  // 当前详情展示的协议全文（点击条目时从 rawfile 读取，带缓存）
  @State licenseText: string = '';
  private textCache: Map<string, string> = new Map();
  private licensesScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.items = buildLicenseItems();
  }

  @Builder
  detailBody(item: LicenseItem) {
    Column() {
      // 固定头部：名称 / 版本与协议 / 用途说明 / 主页链接（次要操作）
      Column({ space: 4 }) {
        Text(item.name)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
        Text(this.itemSub(item))
          .fontSize(13)
          .fontColor(this.pal.sub)
        Text(item.description)
          .fontSize(13)
          .fontColor(this.pal.text)
          .lineHeight(19)
          .margin({ top: 4 })
        Row({ space: 6 }) {
          AppIcon({ name: 'open_in_new', iconSize: 14, tint: this.pal.primary })
          Text($r('app.string.licenses_open_homepage'))
            .fontSize(13)
            .fontColor(this.pal.primary)
        }
        .margin({ top: 10 })
        .onClick(() => {
          const context = Util.hostAbilityContext(this.getUIContext());
          Util.openUrl(context, item.url);
        })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: 24, right: 24, top: 12 })

      Divider()
        .color(this.pal.divider)
        .margin({ left: 24, right: 24, top: 12 })

      // 协议全文：应用内滚动阅读（对齐 aboutlibraries 详情 sheet 的内嵌协议正文）
      Text($r('app.string.licenses_full_text'))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.pal.sub)
        .width('100%')
        .padding({ left: 24, right: 24, top: 10 })
      Scroll() {
        Text(this.licenseText)
          .fontSize(12)
          .fontColor(this.pal.text)
          .lineHeight(19)
          .width('100%')
          .padding({ left: 24, right: 24, bottom: 28 })
          .copyOption(CopyOptions.LocalDevice)
      }
      .layoutWeight(1)
      .width('100%')
      .margin({ top: 4 })
      .scrollBar(BarState.Auto)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  detailBuilder() {
    Column() {
      if (this.selectedIndex >= 0 && this.selectedIndex < this.items.length) {
        this.detailBody(this.items[this.selectedIndex])
      }
    }
    .width('100%')
    .height('100%')
  }

  build() {
    NavGlassPage({ title: $r('app.string.licenses_title'), scroller: this.licensesScroller }) {
      Column() {
        Scroll(this.licensesScroller) {
          Column({ space: 12 }) {
            Column() {
              ForEach(this.items, (item: LicenseItem, index: number) => {
                LicenseRow({
                  name: item.name,
                  sub: this.itemSub(item),
                  onTap: (): void => {
                    this.selectedIndex = index;
                    this.licenseText = this.loadLicenseText(item.licenseFile);
                    this.showDetail = true;
                  }
                })
              }, (item: LicenseItem) => item.name)
            }
            .backgroundColor(this.pal.card)
            .borderRadius(16)
            .clip(true)
            .width('100%')
            .constraintSize({ maxWidth: 720 })
          }
          .width('100%')
          .padding({
            left: 16,
            right: 16,
            top: 4,
            bottom: 24
          })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.TopStart)
      }
      .width('100%')
      .height('100%')
      .bindSheet($$this.showDetail, this.detailBuilder(),
        SheetPreset.fit(this.windowW, {
          height: SheetSize.MEDIUM,
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          showClose: false
        }))
    }
  }

  // 条目副标题：版本在前 + 协议（无版本时仅协议），如「v1.4.2 · BSD-2-Clause」
  private itemSub(item: LicenseItem): string {
    return item.version !== '' ? `v${item.version} · ${item.license}` : item.license;
  }

  // 从 rawfile 读取协议全文（按文件名缓存，避免重复 IO）
  private loadLicenseText(fileName: string): string {
    if (fileName === '') {
      return '';
    }
    const cached: string | undefined = this.textCache.get(fileName);
    if (cached !== undefined) {
      return cached;
    }
    try {
      const ctx = this.getUIContext().getHostContext();
      if (ctx === undefined) {
        return '';
      }
      const text: string = Util.decodeBytes(ctx.resourceManager.getRawFileContentSync(fileName));
      this.textCache.set(fileName, text);
      return text;
    } catch (e) {
      return '';
    }
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function LicensesBuilder() {
  LicensesPage()
}
