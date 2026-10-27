import { webview } from '@kit.ArkWeb';
import { ThemePalette } from '../../common/Theme';
import { Util } from '../../common/Util';
import { Settings } from '../../common/Settings';
import { Log } from '../../common/Log';
import { AppKeys } from '../../common/AppKeys';
import { AppDb } from '../../data/AppDb';
import { CookieJar } from '../../net/CookieJar';
import { Http } from '../../net/Http';
import { Doh } from '../../net/Doh';
import { CrashLogs } from '../../data/CrashLogs';
import { MangaRepo } from '../../data/Repos';
import { MangaRecord } from '../../model/Models';
import { SourceRegistry } from '../../source/Source';
import { NavGlassPage } from '../../common/HdsNavHost';
import { IconRow, PrefGroup, PrefSelectRow, PrefSwitchRow, TextRow } from '../components/Prefs';
import { ConfirmDialog, InputDialog } from '../components/Dialogs';
import { OnboardingParams } from '../../model/RouteParams';

// 高级设置内容（对齐 Mihon SettingsAdvancedScreen，按平台裁剪）：
// 诊断（故障日志导出/详细日志/调试信息/新手引导）
// 数据（清理数据库）· 网络（Cookie/WebView 数据/DoH/UA）· 书库（封面/阅读器标志）
// · 阅读器（高质量渲染）
@Component
export struct AdvancedContent {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  // 长任务进行中（刷新封面等），防重复触发
  @State busy: boolean = false;
  // UA 响应式镜像：Settings 非响应式，编辑/重置后须手动刷新行文本
  @State userAgent: string = Settings.getUserAgent();
  private disposed: boolean = false;
  // 打开新手引导/调试信息（由宿主注入导航；lg 双栏与窄屏壳均 push 路由）
  onOpenOnboarding: () => void = () => {
  };
  onOpenDebugInfo: () => void = () => {
  };

  aboutToDisappear(): void {
    this.disposed = true;
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        // ---- 诊断 ----
        PrefGroup() {
          TextRow({
            title: $r('app.string.pref_dump_crash_logs'),
            onTap: (): void => {
              this.dumpCrashLogs();
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.pref_verbose_logging'),
            subtitle: $r('app.string.pref_verbose_logging_summary'),
            initValue: Settings.getVerboseLogging(),
            apply: (value: boolean): void => {
              Settings.setVerboseLogging(value);
              Log.applyVerboseLogging();
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          TextRow({
            title: $r('app.string.pref_debug_info'),
            onTap: (): void => {
              this.onOpenDebugInfo();
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          IconRow({
            title: $r('app.string.pref_onboarding_guide'),
            icon: 'rocket_launch',
            onTap: (): void => {
              this.onOpenOnboarding();
            }
          })
        }

        // ---- 数据 ----
        PrefGroup({ groupTitle: $r('app.string.pref_group_data') }) {
          TextRow({
            title: $r('app.string.pref_clear_database'),
            onTap: (): void => {
              this.confirmClearDatabase();
            }
          })
        }

        // ---- 网络 ----
        PrefGroup({ groupTitle: $r('app.string.pref_group_network') }) {
          TextRow({
            title: $r('app.string.advanced_clear_cookies'),
            onTap: (): void => {
              CookieJar.clear();
              Util.toastRes(this.getUIContext(), $r('app.string.advanced_cookies_cleared'));
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          TextRow({
            title: $r('app.string.pref_clear_webview_data'),
            onTap: (): void => {
              this.clearWebViewData();
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSelectRow({
            title: $r('app.string.pref_dns_over_https'),
            options: this.dohOptions(),
            selectedIndex: this.dohIndex(),
            onSelectIndex: (index: number): void => {
              this.onDohSelect(index);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          TextRow({
            title: $r('app.string.pref_user_agent_string'),
            value: this.userAgent,
            onTap: (): void => {
              this.editUserAgent();
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          TextRow({
            title: $r('app.string.pref_reset_user_agent'),
            onTap: (): void => {
              this.resetUserAgent();
            }
          })
        }

        // ---- 书库 ----
        PrefGroup({ groupTitle: $r('app.string.pref_group_library') }) {
          TextRow({
            title: $r('app.string.pref_refresh_library_covers'),
            onTap: (): void => {
              this.refreshLibraryCovers();
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          TextRow({
            title: $r('app.string.pref_reset_viewer_flags'),
            onTap: (): void => {
              this.confirmResetViewerFlags();
            }
          })
        }

        // ---- 阅读器 ----
        PrefGroup({ groupTitle: $r('app.string.pref_group_reader') }) {
          PrefSwitchRow({
            title: $r('app.string.pref_high_quality_renderer'),
            subtitle: $r('app.string.pref_high_quality_renderer_summary'),
            initValue: Settings.getReaderHighQuality(),
            apply: (value: boolean): void => {
              Settings.setReaderHighQuality(value);
            }
          })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
  }

  // ---- 诊断 ----

  // 故障日志导出：>0 成功条数；0 无故障；-1 用户取消
  private dumpCrashLogs(): void {
    const context = Util.hostAbilityContext(this.getUIContext());
    CrashLogs.export(context).then((count: number) => {
      if (this.disposed) {
        return;
      }
      if (count === 0) {
        Util.toastRes(this.getUIContext(), $r('app.string.pref_no_crash_logs'));
      } else if (count > 0) {
        Util.toastRes(this.getUIContext(), $r('app.string.pref_crash_logs_saved'), [count]);
      }
    }).catch((_e: Error) => {
      if (!this.disposed) {
        Util.toastRes(this.getUIContext(), $r('app.string.pref_action_failed'));
      }
    });
  }

  // ---- 数据 ----

  private confirmClearDatabase(): void {
    const dialog = new CustomDialogController({
      builder: ConfirmDialog({
        title: $r('app.string.pref_clear_database'),
        message: $r('app.string.pref_clear_database_confirm'),
        onConfirm: (): void => {
          this.doClearDatabase();
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  private async doClearDatabase(): Promise<void> {
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      await AppDb.ready(context);
      const count = await MangaRepo.clearNonLibrary();
      if (this.disposed) {
        return;
      }
      Util.toastRes(this.getUIContext(), $r('app.string.pref_database_cleared'), [count]);
    } catch (_e) {
      if (!this.disposed) {
        Util.toastRes(this.getUIContext(), $r('app.string.pref_action_failed'));
      }
    }
  }

  // ---- 网络 ----

  // 清除内嵌网页（ArkWeb）存储/Cookie/缓存（对齐 Mihon Clear WebView data）
  private clearWebViewData(): void {
    try {
      webview.WebStorage.deleteAllData();
    } catch (_e) {
    }
    try {
      webview.WebCookieManager.clearAllCookiesSync();
    } catch (_e) {
    }
    try {
      const controller = new webview.WebviewController();
      controller.removeCache(true);
    } catch (_e) {
    }
    Util.toastRes(this.getUIContext(), $r('app.string.pref_webview_data_deleted'));
  }

  private dohOptions(): ResourceStr[] {
    const options: ResourceStr[] = [$r('app.string.pref_doh_disabled')];
    for (const p of Doh.PROVIDERS) {
      options.push(p.label);
    }
    return options;
  }

  private dohIndex(): number {
    const id: string = Settings.getDohProvider();
    if (id === '') {
      return 0;
    }
    for (let i = 0; i < Doh.PROVIDERS.length; i++) {
      if (Doh.PROVIDERS[i].id === id) {
        return i + 1;
      }
    }
    return 0;
  }

  private onDohSelect(index: number): void {
    if (index <= 0) {
      Settings.setDohProvider('');
    } else if (index - 1 < Doh.PROVIDERS.length) {
      Settings.setDohProvider(Doh.PROVIDERS[index - 1].id);
    }
    // 切换/关闭后清空既有 host 映射，后续请求按新设置重新解析
    Doh.reset();
  }

  private editUserAgent(): void {
    const dialog = new CustomDialogController({
      builder: InputDialog({
        title: $r('app.string.pref_user_agent_string'),
        placeholder: $r('app.string.pref_user_agent_hint'),
        initialText: Settings.getUserAgent(),
        onConfirm: (text: string): void => {
          // 输入留空等同恢复默认 UA
          Settings.setUserAgent(text.trim());
          Http.syncUserAgent();
          this.userAgent = Settings.getUserAgent();
          Util.toastRes(this.getUIContext(), $r('app.string.pref_user_agent_saved'));
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  private resetUserAgent(): void {
    Settings.setUserAgent('');
    Http.syncUserAgent();
    this.userAgent = Settings.getUserAgent();
    Util.toastRes(this.getUIContext(), $r('app.string.pref_user_agent_saved'));
  }

  // ---- 书库 ----

  // 刷新书库封面：逐源拉取详情并回写元数据（对齐 Mihon MetadataUpdateJob 的封面刷新）
  private async refreshLibraryCovers(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    Util.toastRes(this.getUIContext(), $r('app.string.pref_covers_refresh_started'));
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      await AppDb.ready(context);
      const library: MangaRecord[] = await MangaRepo.getLibrary();
      let cursor = 0;
      const worker = async (): Promise<void> => {
        while (cursor < library.length) {
          const record = library[cursor];
          cursor++;
          const source = SourceRegistry.get(record.sourceKey);
          if (source === undefined) {
            continue;
          }
          try {
            const detail = await source.getWorkDetail(record.url);
            await MangaRepo.upsertFromSource(record.sourceKey, detail, source.contentType);
          } catch (_e) {
            // 单作品失败跳过，不阻断整体刷新
          }
        }
      };
      const workers: Promise<void>[] = [];
      for (let i = 0; i < 3; i++) {
        workers.push(worker());
      }
      await Promise.all(workers);
      AppStorage.setOrCreate(AppKeys.LIB_DIRTY,
        (AppStorage.get<number>(AppKeys.LIB_DIRTY) ?? 0) + 1);
      if (!this.disposed) {
        Util.toastRes(this.getUIContext(), $r('app.string.pref_covers_refreshed'), [library.length]);
      }
    } catch (_e) {
      if (!this.disposed) {
        Util.toastRes(this.getUIContext(), $r('app.string.pref_action_failed'));
      }
    }
    this.busy = false;
  }

  private confirmResetViewerFlags(): void {
    const dialog = new CustomDialogController({
      builder: ConfirmDialog({
        title: $r('app.string.pref_reset_viewer_flags'),
        message: $r('app.string.pref_reset_viewer_flags_summary'),
        onConfirm: (): void => {
          const count = Settings.resetViewerFlags();
          Util.toastRes(this.getUIContext(), $r('app.string.pref_viewer_flags_reset'), [count]);
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }
}

// 高级设置路由壳（手机/平板窄屏 push 进入）
@Component
export struct AdvancedPage {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  // 路由栈：NavDestination onReady 时从自身上下文获取（官方推荐方式）
  pathStack: NavPathStack = new NavPathStack();

  build() {
    NavGlassPage({
      title: $r('app.string.advanced_title'),
      onReady: (ctx: NavDestinationContext): void => {
        this.pathStack = ctx.pathStack;
      }
    }) {
      Column() {
        AdvancedContent({
          onOpenOnboarding: (): void => {
            const params: OnboardingParams = { firstRun: false };
            this.pathStack.pushPathByName('Onboarding', params);
          },
          onOpenDebugInfo: (): void => {
            this.pathStack.pushPathByName('DebugInfo', null);
          }
        })
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function AdvancedBuilder() {
  AdvancedPage()
}
