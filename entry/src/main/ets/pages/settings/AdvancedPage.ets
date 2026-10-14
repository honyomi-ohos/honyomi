import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { Util } from '../../common/Util';
import { CookieJar } from '../../net/CookieJar';
import { PageHeader } from '../components/PageHeader';
import { PrefGroup, TextRow } from '../components/Prefs';
import { InputDialog } from '../components/Dialogs';

// 高级设置内容：Cookie / AniList（备份、章节缓存清理已移至「数据与存储」）
@Component
export struct AdvancedContent {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State tokenLabel: string = '';

  aboutToAppear(): void {
    this.tokenLabel = Settings.getAnilistToken() === '' ?
      Util.resStr(this.getUIContext(), $r('app.string.advanced_token_not_set')) :
      Util.resStr(this.getUIContext(), $r('app.string.advanced_token_set'));
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
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  build() {
    Scroll() {
      Column() {
        PrefGroup() {
          TextRow({
            title: $r('app.string.advanced_clear_cookies'),
            onTap: (): void => {
              CookieJar.clear();
              Util.toastRes(this.getUIContext(), $r('app.string.advanced_cookies_cleared'));
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
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
  }
}

// 高级设置路由壳（手机/平板窄屏 push 进入）
@Component
export struct AdvancedPage {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.advanced_title') })
        AdvancedContent()
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
export function AdvancedBuilder() {
  AdvancedPage()
}
