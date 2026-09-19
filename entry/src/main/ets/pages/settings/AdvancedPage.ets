import { common } from '@kit.AbilityKit';
import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { Util } from '../../common/Util';
import { ImageCache } from '../../common/ImageCache';
import { CookieJar } from '../../net/CookieJar';
import { BackupService } from '../../data/BackupService';
import { PageHeader } from '../components/PageHeader';
import { PrefGroup, TextRow } from '../components/Prefs';
import { InputDialog } from '../components/Dialogs';

// 高级设置：缓存 / Cookie / 备份 / AniList
@Component
export struct AdvancedPage {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State cacheLabel: string = '计算中…';
  @State tokenLabel: string = '未配置';
  @State busy: boolean = false;

  aboutToAppear(): void {
    this.refreshCacheLabel();
    this.tokenLabel = Settings.getAnilistToken() === '' ? '未配置' : '已配置';
  }

  private refreshCacheLabel(): void {
    const bytes = ImageCache.size();
    if (bytes >= 1024 * 1024) {
      this.cacheLabel = `${(bytes / 1024 / 1024).toFixed(1)} MB`;
    } else if (bytes >= 1024) {
      this.cacheLabel = `${Math.round(bytes / 1024)} KB`;
    } else {
      this.cacheLabel = `${bytes} B`;
    }
  }

  private showTokenDialog(): void {
    const dialog = new CustomDialogController({
      builder: InputDialog({
        title: 'AniList 访问令牌',
        placeholder: '粘贴 access token（留空清除）',
        onConfirm: (text: string): void => {
          const token = text.trim();
          Settings.setAnilistToken(token);
          this.tokenLabel = token === '' ? '未配置' : '已配置';
          Util.toast(this.getUIContext(), token === '' ? '已清除令牌' : '已保存令牌');
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  private async doExport(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const ok = await BackupService.exportBackup(context);
      Util.toast(this.getUIContext(), ok ? '备份已导出' : '已取消导出');
    } catch (e) {
      Util.toast(this.getUIContext(), '导出失败');
    }
    this.busy = false;
  }

  private async doImport(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const count = await BackupService.importBackup(context);
      if (count === -1) {
        Util.toast(this.getUIContext(), '已取消导入');
      } else if (count === -2) {
        Util.toast(this.getUIContext(), '备份文件无效');
      } else {
        Util.toast(this.getUIContext(), `已恢复 ${count} 部漫画`);
        AppStorage.setOrCreate('libDirty', (AppStorage.get<number>('libDirty') ?? 0) + 1);
      }
    } catch (e) {
      Util.toast(this.getUIContext(), '导入失败');
    }
    this.busy = false;
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '高级' })
        Scroll() {
          Column() {
            PrefGroup({ groupTitle: '存储' }) {
              TextRow({
                title: '清除图片缓存',
                value: this.cacheLabel,
                onTap: (): void => {
                  ImageCache.clearAll();
                  this.refreshCacheLabel();
                  Util.toast(this.getUIContext(), '已清除图片缓存');
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              TextRow({
                title: '清除 Cookie',
                onTap: (): void => {
                  CookieJar.clear();
                  Util.toast(this.getUIContext(), '已清除全部 Cookie');
                }
              })
            }

            PrefGroup({ groupTitle: '备份与还原' }) {
              TextRow({
                title: '导出备份',
                value: 'JSON',
                onTap: (): void => {
                  this.doExport();
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              TextRow({
                title: '导入备份',
                value: 'JSON',
                onTap: (): void => {
                  this.doImport();
                }
              })
            }

            PrefGroup({ groupTitle: '追踪服务' }) {
              TextRow({
                title: 'AniList 令牌',
                value: this.tokenLabel,
                onTap: (): void => {
                  this.showTokenDialog();
                }
              })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 24 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.TopStart)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
  }
}
