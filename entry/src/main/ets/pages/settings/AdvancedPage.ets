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
  @State cacheLabel: string = '';
  @State tokenLabel: string = '';
  @State busy: boolean = false;

  aboutToAppear(): void {
    this.cacheLabel = Util.resStr(this.getUIContext(), $r('app.string.advanced_calculating'));
    this.refreshCacheLabel();
    this.tokenLabel = Settings.getAnilistToken() === '' ?
      Util.resStr(this.getUIContext(), $r('app.string.advanced_token_not_set')) :
      Util.resStr(this.getUIContext(), $r('app.string.advanced_token_set'));
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
        title: $r('app.string.advanced_token_title'),
        placeholder: $r('app.string.advanced_token_hint'),
        onConfirm: (text: string): void => {
          const token = text.trim();
          Settings.setAnilistToken(token);
          this.tokenLabel = token === '' ?
            Util.resStr(this.getUIContext(), $r('app.string.advanced_token_not_set')) :
            Util.resStr(this.getUIContext(), $r('app.string.advanced_token_set'));
          Util.toastRes(this.getUIContext(), token === '' ?
            $r('app.string.advanced_token_cleared') : $r('app.string.advanced_token_saved'));
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
      Util.toastRes(this.getUIContext(), ok ? $r('app.string.advanced_backup_exported') : $r('app.string.advanced_export_canceled'));
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.advanced_export_failed'));
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
        Util.toastRes(this.getUIContext(), $r('app.string.advanced_import_canceled'));
      } else if (count === -2) {
        Util.toastRes(this.getUIContext(), $r('app.string.advanced_backup_invalid'));
      } else {
        Util.toastRes(this.getUIContext(), $r('app.string.advanced_restored_manga'), [count]);
        AppStorage.setOrCreate('libDirty', (AppStorage.get<number>('libDirty') ?? 0) + 1);
      }
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.advanced_import_failed'));
    }
    this.busy = false;
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.advanced_title') })
        Scroll() {
          Column() {
            PrefGroup({ groupTitle: $r('app.string.advanced_storage') }) {
              TextRow({
                title: $r('app.string.advanced_clear_image_cache'),
                value: this.cacheLabel,
                onTap: (): void => {
                  ImageCache.clearAll();
                  this.refreshCacheLabel();
                  Util.toastRes(this.getUIContext(), $r('app.string.advanced_image_cache_cleared'));
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              TextRow({
                title: $r('app.string.advanced_clear_cookies'),
                onTap: (): void => {
                  CookieJar.clear();
                  Util.toastRes(this.getUIContext(), $r('app.string.advanced_cookies_cleared'));
                }
              })
            }

            PrefGroup({ groupTitle: $r('app.string.advanced_backup_restore') }) {
              TextRow({
                title: $r('app.string.advanced_export_backup'),
                value: 'JSON',
                onTap: (): void => {
                  this.doExport();
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              TextRow({
                title: $r('app.string.advanced_import_backup'),
                value: 'JSON',
                onTap: (): void => {
                  this.doImport();
                }
              })
            }

            PrefGroup({ groupTitle: $r('app.string.advanced_tracking') }) {
              TextRow({
                title: $r('app.string.advanced_anilist_token'),
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
