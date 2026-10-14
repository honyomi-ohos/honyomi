import { common } from '@kit.AbilityKit';
import { statfs } from '@kit.CoreFileKit';
import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { Util } from '../../common/Util';
import { ImageCache } from '../../common/ImageCache';
import { BackupService } from '../../data/BackupService';
import { PageHeader } from '../components/PageHeader';
import { PrefGroup, TextRow, PrefSelectRow, PrefSwitchRow } from '../components/Prefs';
import { ExportColumnsDialog } from '../components/Dialogs';
import { AppIcon } from '../components/AppIcon';

const HELP_URL: string = 'https://mihon.app/docs/faq/storage';
// 备份频率选项（小时）：关闭 / 6 / 12 / 24 / 48 / 每周（对齐 Mihon backupInterval）
const INTERVAL_HOURS: number[] = [0, 6, 12, 24, 48, 168];

// 数据与存储内容（对齐 Mihon SettingsDataScreen）：
// 存储位置 / 备份与还原（手动+自动）/ 存储占用（磁盘信息+章节缓存）/ 导出（书架列表 CSV）
@Component
export struct DataStorageContent {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  // 自动备份失败状态（BackupService 写入）：true 时展示失败提示条
  @StorageProp('lastBackupFailed') lastBackupFailed: boolean = false;
  @State cacheLabel: string = '';
  @State usedPercent: number = 0;
  @State spaceText: string = '—';
  @State lastBackupText: string = '';
  @State busy: boolean = false;
  // 页面销毁标志：异步续体据此跳过 toast/写状态
  private disposed: boolean = false;

  aboutToAppear(): void {
    this.refreshCacheLabel();
    this.refreshStorageInfo();
    this.refreshLastBackup();
  }

  aboutToDisappear(): void {
    this.disposed = true;
  }

  private refreshCacheLabel(): void {
    this.cacheLabel = Util.resStr(this.getUIContext(), $r('app.string.data_used_cache'),
      [Util.formatBytes(ImageCache.size())]);
  }

  // 磁盘占用：内部存储 已用/总量（filesDir 所在分区）
  private refreshStorageInfo(): void {
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      const total: number = statfs.getTotalSizeSync(context.filesDir);
      const free: number = statfs.getFreeSizeSync(context.filesDir);
      if (total > 0 && free >= 0) {
        this.usedPercent = Math.round(((total - free) / total) * 100);
        this.spaceText = Util.resStr(this.getUIContext(), $r('app.string.data_available_space'),
          [Util.formatBytes(free), Util.formatBytes(total)]);
      }
    } catch (e) {
      // 获取失败保持占位
    }
  }

  private refreshLastBackup(): void {
    const ui = this.getUIContext();
    const last: number = Settings.getLastAutoBackupTimestamp();
    if (last <= 0) {
      this.lastBackupText = Util.resStr(ui, $r('app.string.data_never_backed_up'));
      return;
    }
    const rel: Resource | string = Util.timeAgo(last);
    const relText: string = typeof rel === 'string' ? rel : Util.resStr(ui, rel);
    this.lastBackupText = Util.resStr(ui, $r('app.string.data_last_auto_backup'), [relText]);
  }

  // ---- 备份与还原 ----

  private async doCreateBackup(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      const ok = await BackupService.exportBackup(context);
      if (this.disposed) {
        return;
      }
      Util.toastRes(this.getUIContext(), ok ? $r('app.string.advanced_backup_exported') :
        $r('app.string.advanced_export_canceled'));
    } catch (e) {
      if (this.disposed) {
        return;
      }
      Util.toastRes(this.getUIContext(), $r('app.string.advanced_export_failed'));
    }
    if (!this.disposed) {
      this.busy = false;
    }
  }

  private async doRestoreBackup(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      const count = await BackupService.importBackup(context);
      if (this.disposed) {
        return;
      }
      if (count === -1) {
        Util.toastRes(this.getUIContext(), $r('app.string.advanced_import_canceled'));
      } else if (count === -2) {
        Util.toastRes(this.getUIContext(), $r('app.string.advanced_backup_invalid'));
      } else {
        Util.toastRes(this.getUIContext(), $r('app.string.advanced_restored_manga'), [count]);
        AppStorage.setOrCreate('libDirty', (AppStorage.get<number>('libDirty') ?? 0) + 1);
      }
    } catch (e) {
      if (this.disposed) {
        return;
      }
      Util.toastRes(this.getUIContext(), $r('app.string.advanced_import_failed'));
    }
    if (!this.disposed) {
      this.busy = false;
    }
  }

  private onIntervalSelect(index: number): void {
    if (index < 0 || index >= INTERVAL_HOURS.length) {
      return;
    }
    Settings.setBackupInterval(INTERVAL_HOURS[index]);
  }

  // ---- 存储占用 ----

  private clearChapterCache(): void {
    const deleted: number = ImageCache.count();
    ImageCache.clearAll();
    this.refreshCacheLabel();
    Util.toastRes(this.getUIContext(), $r('app.string.data_cache_deleted'), [deleted]);
  }

  // ---- 导出 ----

  private showExportDialog(): void {
    const dialog = new CustomDialogController({
      builder: ExportColumnsDialog({
        onConfirm: (includeTitle: boolean, includeAuthor: boolean): void => {
          this.doExportCsv(includeTitle, includeAuthor);
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  private async doExportCsv(includeTitle: boolean, includeAuthor: boolean): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      const ok = await BackupService.exportLibraryCsv(context, includeTitle, includeAuthor);
      Util.toastRes(this.getUIContext(), ok ? $r('app.string.data_library_exported') :
        $r('app.string.data_export_canceled'));
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.data_export_failed'));
    }
    this.busy = false;
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        // 存储位置
        PrefGroup() {
          TextRow({
            title: $r('app.string.data_storage_location'),
            value: $r('app.string.data_storage_location_value'),
            onTap: (): void => {
              const context = Util.hostAbilityContext(this.getUIContext());
              Util.toast(this.getUIContext(), context.filesDir);
            }
          })
        }
        Text($r('app.string.data_storage_location_info'))
          .fontSize(12)
          .fontColor(this.pal.sub)
          .margin({ left: 20 })
          .constraintSize({ maxWidth: 680 })

        // 备份与还原
        PrefGroup({ groupTitle: $r('app.string.data_backup_restore') }) {
          Row() {
            Button($r('app.string.data_create_backup'))
              .layoutWeight(1)
              .height(40)
              .borderRadius({ topLeft: 20, bottomLeft: 20 })
              .backgroundColor(this.pal.chip)
              .fontColor(this.pal.text)
              .fontSize(14)
              .onClick(() => {
                this.doCreateBackup();
              })
            Button($r('app.string.data_restore_backup'))
              .layoutWeight(1)
              .height(40)
              .borderRadius({ topRight: 20, bottomRight: 20 })
              .backgroundColor(this.pal.chip)
              .fontColor(this.pal.text)
              .fontSize(14)
              .onClick(() => {
                this.doRestoreBackup();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })

          Divider().color(this.pal.divider).margin({ left: 16 })

          PrefSelectRow({
            title: $r('app.string.data_backup_interval'),
            options: [
              $r('app.string.data_interval_off'),
              $r('app.string.data_interval_6h'),
              $r('app.string.data_interval_12h'),
              $r('app.string.data_interval_24h'),
              $r('app.string.data_interval_48h'),
              $r('app.string.data_interval_weekly')
            ],
            selectedIndex: INTERVAL_HOURS.indexOf(Settings.getBackupInterval()),
            onSelectIndex: (index: number): void => {
              this.onIntervalSelect(index);
            }
          })

          Divider().color(this.pal.divider).margin({ left: 16 })

          // 上次自动备份失败提示条
          if (this.lastBackupFailed) {
            Text($r('app.string.last_backup_failed_hint'))
              .fontSize(12)
              .fontColor('#D32F2F')
              .padding({ left: 16, right: 16, top: 10 })
          }

          Text($r('app.string.data_backup_info'))
            .fontSize(12)
            .fontColor(this.pal.sub)
            .padding({ left: 16, right: 16, top: 10, bottom: 2 })
          Text(this.lastBackupText)
            .fontSize(12)
            .fontColor(this.pal.sub)
            .padding({ left: 16, right: 16, bottom: 12 })
        }

        // 存储占用
        PrefGroup({ groupTitle: $r('app.string.data_storage_usage') }) {
          Column({ space: 8 }) {
            Text($r('app.string.data_storage_name'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.pal.text)
            Progress({ value: this.usedPercent, total: 100, type: ProgressType.Linear })
              .height(12)
              .borderRadius(6)
              .color(this.pal.primary)
              .backgroundColor(this.pal.chip)
            Text(this.spaceText)
              .fontSize(12)
              .fontColor(this.pal.sub)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })

          Divider().color(this.pal.divider).margin({ left: 16 })

          TextRow({
            title: $r('app.string.data_clear_chapter_cache'),
            value: this.cacheLabel,
            onTap: (): void => {
              this.clearChapterCache();
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.data_auto_clear_cache'),
            initValue: Settings.getAutoClearChapterCache(),
            apply: (value: boolean): void => {
              Settings.setAutoClearChapterCache(value);
            }
          })
        }

        // 导出
        PrefGroup({ groupTitle: $r('app.string.data_export') }) {
          TextRow({
            title: $r('app.string.data_library_list'),
            onTap: (): void => {
              this.showExportDialog();
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
}

// 数据与存储路由壳（手机/平板窄屏 push 进入）
@Component
export struct DataStoragePage {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.data_storage_title') }) {
          AppIcon({ name: 'help', iconSize: 22 })
            .padding(8)
            .onClick(() => {
              const context = Util.hostAbilityContext(this.getUIContext());
              Util.openUrl(context, HELP_URL);
            })
        }
        DataStorageContent()
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function DataStorageBuilder() {
  DataStoragePage()
}
