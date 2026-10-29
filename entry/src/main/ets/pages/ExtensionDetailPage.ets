import { InstalledPlugin, PluginService } from '../data/PluginService';
import { ContentType } from '../model/Models';
import { Source, SourceRegistry } from '../source/Source';
import { JsvmSource, SourcePrefItem, SourcePrefOption } from '../source/JsvmSource';
import { BrowseSourceParams, ExtensionDetailParams } from '../model/RouteParams';
import { ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { Bp } from '../common/Breakpoint';
import { Settings } from '../common/Settings';
import { EmptyScreen } from './components/EmptyScreen';
import { ConfirmDialog, InputDialog } from './components/Dialogs';
import { AppIcon } from './components/AppIcon';
import { TypeBadgedIcon } from './components/TypeBadgedIcon';
import { NsfwTag } from './components/NsfwTag';
import { BtTag } from './components/BtTag';

// 语言显示名（与 BrowsePage 保持一致的精简版）
const LANG_NAMES: Record<string, string> = {
  'en': 'English',
  'ja': '日本語',
  'zh': '中文',
  'zh-Hans': '中文',
  'zh-Hant': '中文（繁）',
  'ko': '한국어',
  'multi': 'Multi',
  'all': 'Multi',
};

function langDisplayName(lang: string): string {
  const name: string | undefined = LANG_NAMES[lang];
  return name !== undefined ? name : lang.toUpperCase();
}

// 设置项取值弹窗（select 型偏好）
@CustomDialog
struct PrefSelectDialog {
  controller?: CustomDialogController;
  title: Resource | string = '';
  options: SourcePrefOption[] = [];
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  onPick: (value: string) => void = (_v: string) => {
  };
  onClose: () => void = () => {
  };

  build() {
    Column({ space: 8 }) {
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ bottom: 8 })
      Scroll() {
        Column() {
          ForEach(this.options, (opt: SourcePrefOption) => {
            Text(opt.label)
              .fontSize(15)
              .fontColor(this.pal.text)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding(12)
              .borderRadius(10)
              .backgroundColor(this.pal.chip)
              .onClick(() => {
                this.dismiss();
                this.onPick(opt.value);
              })
          }, (opt: SourcePrefOption) => `opt-${opt.value}`)
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 300 })
      .scrollBar(BarState.Off)
    }
    .padding(20)
    .width('100%')
  }

  private dismiss(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
    this.onClose();
  }
}

// 插件详情/设置页（对齐 Mihon ExtensionDetailsScreen）：
// 头部信息 + 卸载按钮 + 源入口 + 插件自定义设置（getSettingsSchema 声明）
@Component
export struct ExtensionDetailPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageProp('navBarH') navBarH: number = 0;
  @StorageProp('windowW') windowW: number = 0;
  @State pluginKey: string = '';
  @State plugin: InstalledPlugin | undefined = undefined;
  @State schema: SourcePrefItem[] = [];
  @State loadingSchema: boolean = false;
  // 设置来源：true = manifest 静态声明（宿主直读直写，不拉引擎）
  @State manifestSettings: boolean = false;
  @State busy: boolean = false;
  // 按插件隐身（对齐 Mihon incognito extensions）：浏览该插件的源时不记录历史/统计
  @State incognitoMode: boolean = false;
  // 页面已销毁标志：await 返回后组件可能已析构，禁止再访问 UIContext/执行导航
  private destroyed: boolean = false;

  aboutToDisappear(): void {
    this.destroyed = true;
  }

  @Builder
  infoCell(primary: string, secondary: ResourceStr) {
    Column() {
      Text(primary)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(secondary)
        .fontSize(11)
        .fontColor(this.pal.sub)
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  prefRow(item: SourcePrefItem) {
    if (item.type === 'switch') {
      Row() {
        Column() {
          Text(item.title)
            .fontSize(15)
            .fontColor(this.pal.text)
          if (item.summary !== '') {
            Text(item.summary)
              .fontSize(11)
              .fontColor(this.pal.sub)
              .margin({ top: 2 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: item.value === 'true' })
          .onChange((on: boolean) => {
            if (on !== (item.value === 'true')) {
              this.applyPref(item, on ? 'true' : 'false');
            }
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ top: 10, bottom: 10 })
    } else if (item.type === 'select') {
      Row() {
        Column() {
          Text(item.title)
            .fontSize(15)
            .fontColor(this.pal.text)
          Text(this.currentLabelOf(item))
            .fontSize(11)
            .fontColor(this.pal.sub)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        AppIcon({ name: 'keyboard_arrow_right', iconSize: 20, tint: this.pal.sub })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ top: 10, bottom: 10 })
      .onClick(() => {
        this.showSelectPrefDialog(item);
      })
    } else {
      Row() {
        Column() {
          Text(item.title)
            .fontSize(15)
            .fontColor(this.pal.text)
          // 敏感项已设值时掩码显示（不回显明文）
          Text(item.value !== '' ? (item.sensitive ? '••••••••' : item.value) : item.summary)
            .fontSize(11)
            .fontColor(this.pal.sub)
            .margin({ top: 2 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        AppIcon({ name: 'keyboard_arrow_right', iconSize: 20, tint: this.pal.sub })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ top: 10, bottom: 10 })
      .onClick(() => {
        this.showEditPrefDialog(item);
      })
    }
  }

  build() {
    NavDestination() {
      Column() {
        // 顶栏
        Row() {
          AppIcon({ name: 'arrow_back', iconSize: 24 })
            .onClick(() => {
              this.pathStack.pop();
            })
          Text($r('app.string.ext_detail_title'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal.text)
            .margin({ left: 8 })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({
          left: 16 + this.inset(),
          right: 16 + this.inset(),
          top: this.statusBarH + 10,
          bottom: 8
        })

        if (this.plugin === undefined) {
          Column() {
            EmptyScreen({ message: $r('app.string.ext_detail_missing') })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              // 头部：图标 + 名称 + 版本/语言 + 卸载
              Column() {
                TypeBadgedIcon({
                  iconPath: this.plugin.iconPath,
                  fallbackChar: this.plugin.manifest.name.substring(0, 1)
                    .toUpperCase(),
                  iconSize: 72,
                  cornerRadius: 16,
                  contentType: this.plugin.manifest.contentTypes.length > 0 ?
                    this.plugin.manifest.contentTypes[0] : ContentType.MANGA,
                  badgeBorder: this.pal.card,
                })
                  .margin({ top: 8 })

                Row() {
                  Text(this.plugin.manifest.name)
                    .fontSize(20)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.pal.text)
                    .maxLines(2)
                    .textAlign(TextAlign.Center)
                  if (this.plugin.manifest.nsfw) {
                    NsfwTag()
                      .margin({ left: 6 })
                  }
                  if (this.plugin.manifest.bt) {
                    BtTag()
                      .margin({ left: 6 })
                  }
                }
                .alignItems(VerticalAlign.Center)
                .margin({ top: 12 })

                Text(this.plugin.manifest.key)
                  .fontSize(12)
                  .fontColor(this.pal.sub)
                  .margin({ top: 2 })

                Row() {
                  this.infoCell(`v${this.plugin.manifest.version}`, $r('app.string.ext_info_version'))
                  Divider()
                    .vertical(true)
                    .height(24)
                    .color(this.pal.divider)
                  this.infoCell(langDisplayName(this.plugin.manifest.lang), $r('app.string.ext_info_language'))
                }
                .width('100%')
                .margin({ top: 16 })

                Button($r('app.string.common_uninstall'))
                  .fontSize(14)
                  .width('100%')
                  .backgroundColor(this.pal.card)
                  .fontColor('#E05252')
                  .border({ width: 1, color: '#E05252', radius: 20 })
                  .margin({ top: 16 })
                  .onClick(() => {
                    this.confirmUninstall();
                  })

                // 按插件隐身开关（对齐 Mihon DetailsHeader 的 Incognito mode 行）
                Divider()
                  .color(this.pal.divider)
                  .margin({ top: 16 })
                Row() {
                  Column() {
                    Text('隐身浏览')
                      .fontSize(15)
                      .fontColor(this.pal.text)
                    Text('浏览此插件的源时不记录阅读历史与统计')
                      .fontSize(11)
                      .fontColor(this.pal.sub)
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Toggle({ type: ToggleType.Switch, isOn: this.incognitoMode })
                    .selectedColor(this.pal.primary)
                    .onChange((on: boolean) => {
                      if (on !== this.incognitoMode) {
                        this.toggleIncognito(on);
                      }
                    })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .padding({ top: 12 })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
              .padding(20)
              .backgroundColor(this.pal.card)
              .borderRadius(14)
              .margin({ top: 4 })

              // 源入口
              Column() {
                Text($r('app.string.ext_detail_sources'))
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.pal.text)
                  .width('100%')
                  .margin({ bottom: 4 })

                if (this.packageSources().length === 0) {
                  Text($r('app.string.ext_detail_missing'))
                    .fontSize(12)
                    .fontColor(this.pal.sub)
                    .width('100%')
                    .padding({ top: 8, bottom: 8 })
                } else {
                  ForEach(this.packageSources(), (source: Source) => {
                    Row() {
                      Column() {
                        Text(source.name)
                          .fontSize(15)
                          .fontColor(this.pal.text)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Row() {
                          Text(langDisplayName(source.lang))
                            .fontSize(11)
                            .fontColor(this.pal.sub)
                          if (source.nsfw) {
                            NsfwTag()
                              .margin({ left: 6 })
                          }
                          if (source.bt) {
                            BtTag()
                              .margin({ left: 6 })
                          }
                        }
                        .alignItems(VerticalAlign.Center)
                        .margin({ top: 2 })
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)

                      AppIcon({ name: 'keyboard_arrow_right', iconSize: 20, tint: this.pal.sub })
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Center)
                    .padding({ top: 10, bottom: 10 })
                    .onClick(() => {
                      this.openSource(source.key);
                    })
                  }, (source: Source) => `src-${source.key}`)
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(16)
              .backgroundColor(this.pal.card)
              .borderRadius(14)
              .margin({ top: 12 })

              // 插件设置（getSettingsSchema 声明时显示）
              if (this.isConfigurable()) {
                Column() {
                  Text($r('app.string.ext_detail_settings'))
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.pal.text)
                    .width('100%')
                    .margin({ bottom: 4 })

                  if (this.loadingSchema) {
                    Row({ space: 8 }) {
                      LoadingProgress()
                        .width(18)
                        .height(18)
                        .color(this.pal.primary)
                      Text($r('app.string.ext_pref_loading'))
                        .fontSize(12)
                        .fontColor(this.pal.sub)
                    }
                    .width('100%')
                    .padding({ top: 10, bottom: 10 })
                  } else {
                    ForEach(this.schema, (item: SourcePrefItem) => {
                      this.prefRow(item)
                    }, (item: SourcePrefItem) => `pref-${item.key}-${item.value}`)
                  }
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding(16)
                .backgroundColor(this.pal.card)
                .borderRadius(14)
                .margin({ top: 12, bottom: 24 })
              } else {
                Column()
                  .height(24)
              }
            }
            .width('100%')
            // 大屏限宽缩进：滚动容器全宽，内容列经 padding 缩进（卡片 margin+width('100%') 会被父默认居中对齐抵消）
            .padding({ left: 16 + this.inset(), right: 16 + this.inset() })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .align(Alignment.Top)
          .contentEndOffset(this.navBarH + 16)
          .width('100%')
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const params = ctx.pathInfo.param as ExtensionDetailParams;
      const key = params !== undefined && params !== null ? params.pluginKey : '';
      if (key === '') {
        // 参数缺失：保持 plugin undefined，走"插件不存在"占位展示
        return;
      }
      this.pluginKey = key;
      this.incognitoMode = Settings.isPluginIncognito(key);
      this.loadPlugin();
      this.loadSchema();
    })
  }

  private inset(): number {
    return Bp.contentInset(this.windowW);
  }

  private currentSource(): Source | undefined {
    return SourceRegistry.get(this.pluginKey);
  }

  // 已安装插件来自 DB 元数据索引（异步）：按 key 匹配当前插件
  private async loadPlugin(): Promise<void> {
    const installed = await PluginService.listInstalled();
    if (this.destroyed) {
      return;
    }
    for (const item of installed) {
      if (item.manifest.key === this.pluginKey) {
        this.plugin = item;
        break;
      }
    }
  }

  // 插件是否声明了设置页（manifest 静态声明或运行期 getSettingsSchema 契约）
  private isConfigurable(): boolean {
    const src = this.currentSource();
    return src instanceof JsvmSource &&
      (this.manifestSettings || src.hasMethod('getSettingsSchema'));
  }

  private async loadSchema(): Promise<void> {
    this.loadingSchema = true;
    // manifest 静态声明优先：读 manifest.json + PluginPrefs 当前值，不拉起 JSVM 引擎
    try {
      const declared = await PluginService.declaredSettings(this.pluginKey);
      if (declared.length > 0) {
        this.manifestSettings = true;
        this.schema = declared.filter((item: SourcePrefItem): boolean => !item.hidden);
        this.loadingSchema = false;
        return;
      }
    } catch (e) {
      // manifest 读取失败：回退运行期契约
    }
    this.manifestSettings = false;
    const src = this.currentSource();
    if (!(src instanceof JsvmSource) || !src.hasMethod('getSettingsSchema')) {
      this.schema = [];
      this.loadingSchema = false;
      return;
    }
    try {
      const all = await src.getSettingsSchema();
      this.schema = all.filter((item: SourcePrefItem): boolean => !item.hidden);
    } catch (e) {
      this.schema = [];
      if (!this.destroyed) {
        Util.toastRes(this.getUIContext(), $r('app.string.ext_pref_failed'),
          [Util.errText(this.getUIContext(), (e as Error).message)]);
      }
    }
    this.loadingSchema = false;
  }

  // 应用设置项变更：manifest 静态设置宿主直写持久化偏好（不拉引擎）；
  // 运行期契约走插件 setPreference 后刷新声明（回读当前值）
  private async applyPref(item: SourcePrefItem, value: string): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      if (this.manifestSettings) {
        await PluginService.setDeclaredPref(this.pluginKey, item.key, value);
      } else {
        const src = this.currentSource();
        if (src instanceof JsvmSource) {
          await src.setPreference(item.key, value);
        }
      }
      await this.loadSchema();
    } catch (e) {
      if (!this.destroyed) {
        Util.toastRes(this.getUIContext(), $r('app.string.ext_pref_failed'),
          [Util.errText(this.getUIContext(), (e as Error).message)]);
      }
    }
    this.busy = false;
  }

  private currentLabelOf(item: SourcePrefItem): string {
    for (const opt of item.options) {
      if (opt.value === item.value) {
        return opt.label;
      }
    }
    return item.value;
  }

  private confirmUninstall(): void {
    const name = this.plugin !== undefined ? this.plugin.manifest.name : this.pluginKey;
    const dialog = new CustomDialogController({
      builder: ConfirmDialog({
        title: $r('app.string.ext_uninstall_title'),
        message: Util.resStr(this.getUIContext(), $r('app.string.ext_uninstall_msg'), [name]),
        confirmText: $r('app.string.common_uninstall'),
        onConfirm: (): void => {
          this.uninstall();
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  private async uninstall(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      await PluginService.uninstall(this.pluginKey);
      PluginService.markDirty();
      if (!this.destroyed) {
        Util.toastRes(this.getUIContext(), $r('app.string.plugin_uninstalled'), [this.pluginKey]);
        this.pathStack.pop();
      }
    } catch (e) {
      if (!this.destroyed) {
        Util.toastRes(this.getUIContext(), $r('app.string.plugin_uninstall_failed'));
      }
    }
    this.busy = false;
  }

  private showEditPrefDialog(item: SourcePrefItem): void {
    const dialog = new CustomDialogController({
      builder: InputDialog({
        title: item.title,
        placeholder: item.summary,
        initialText: item.value,
        // 敏感项（密码/Token）使用系统密码输入框，自动掩码显示
        password: item.sensitive,
        onConfirm: (text: string): void => {
          this.applyPref(item, text);
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  private showSelectPrefDialog(item: SourcePrefItem): void {
    const dialog = new CustomDialogController({
      builder: PrefSelectDialog({
        title: item.title,
        options: item.options,
        onPick: (value: string): void => {
          this.applyPref(item, value);
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  private packageSources(): Source[] {
    const out: Source[] = [];
    for (const source of SourceRegistry.all()) {
      if (source instanceof JsvmSource && source.packageKey === this.pluginKey) {
        out.push(source);
      } else if (source.key === this.pluginKey) {
        out.push(source);
      }
    }
    return out;
  }

  private openSource(key: string): void {
    const params: BrowseSourceParams = { sourceKey: key, mode: 'popular' };
    this.pathStack.pushPathByName('BrowseSource', params);
  }

  // 按插件隐身开关：从隐身插件列表中增删当前插件 key（列表整体写回，
  // 复用 Settings.setIncognitoPlugins 中心化存储；无痕闸门 HistoryRepo.isIncognitoFor
  // 每次实时读 Settings，无需额外失效通知）
  private toggleIncognito(on: boolean): void {
    const list = Settings.getIncognitoPlugins().filter((k: string): boolean => k !== this.pluginKey);
    if (on) {
      list.push(this.pluginKey);
    }
    Settings.setIncognitoPlugins(list);
    this.incognitoMode = Settings.isPluginIncognito(this.pluginKey);
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function ExtensionDetailBuilder() {
  ExtensionDetailPage()
}
