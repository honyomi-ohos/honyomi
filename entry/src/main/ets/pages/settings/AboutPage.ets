// 关于页（对齐 Mihon AboutScreen）：logo + 版本徽章 + 简介卡片
// + 版本行（点击复制调试信息）/ 开源许可证 / 隐私说明
// 更新日志以文档形式维护在 docs/CHANGELOG.md，后续使用 GitHub Releases 记录
import { ThemePalette } from '../../common/Theme';
import { Util } from '../../common/Util';
import { AppInfo } from '../../common/AppInfo';
import { Bp } from '../../common/Breakpoint';
import { PageHeader } from '../components/PageHeader';
import { IconRow, PrefGroup, TextRow } from '../components/Prefs';
import { pasteboard, BusinessError } from '@kit.BasicServicesKit';

@Component
export struct AboutContent {
  @Consume('navStack') pathStack: NavPathStack;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State versionName: string = '';
  @State versionCode: number = 0;
  inset: number = 0;

  aboutToAppear(): void {
    this.versionName = AppInfo.versionName();
    this.versionCode = AppInfo.versionCode();
  }

  build() {
    Scroll() {
      Column() {
        Image($r('app.media.startIcon'))
          .width(96)
          .height(96)
          .borderRadius(24)
          .border({ width: 0.5, color: this.pal.divider })
          .margin({ top: 32 })
        Text('Honyomi')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
          .letterSpacing(0.5)
          .margin({ top: 16 })
        Text(this.versionName)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal.onPrimarySoft)
          .padding({
            left: 12,
            right: 12,
            top: 4,
            bottom: 4
          })
          .backgroundColor(this.pal.primarySoft)
          .borderRadius(999)
          .margin({ top: 10 })

        Column({ space: 12 }) {
          Column() {
            Text($r('app.string.about_desc'))
              .fontSize(14)
              .fontColor(this.pal.text)
              .lineHeight(22)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(16)
          .backgroundColor(this.pal.card)
          .borderRadius(16)

          PrefGroup() {
            TextRow({
              title: $r('app.string.about_row_version'),
              value: `${this.versionName} (${this.versionCode})`,
              onTap: (): void => {
                this.copyDebugInfo();
              }
            })
            Divider().color(this.pal.divider).margin({ left: 16 })
            IconRow({
              title: $r('app.string.licenses_title'),
              icon: 'public',
              onTap: (): void => {
                this.pathStack.pushPathByName('Licenses', null);
              }
            })
            Divider().color(this.pal.divider).margin({ left: 16 })
            IconRow({
              title: $r('app.string.privacy_policy_title'),
              icon: 'lock',
              onTap: (): void => {
                this.pathStack.pushPathByName('PrivacyPolicy', null);
              }
            })
          }
        }
        .width('100%')
        .padding({ left: 16 + this.inset, right: 16 + this.inset })
        .margin({ top: 24 })
      }
      .width('100%')
      .padding({ bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .align(Alignment.Top)
  }

  // 复制调试信息到剪贴板（对齐 Mihon：点击版本行触发）
  private copyDebugInfo(): void {
    const ui: UIContext = this.getUIContext();
    const data: pasteboard.PasteData =
      pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, AppInfo.debugInfo());
    pasteboard.getSystemPasteboard().setData(data)
      .then(() => {
        Util.toast(ui, Util.resStr(ui, $r('app.string.about_debug_copied')));
      })
      .catch((_e: BusinessError) => {
      });
  }
}

// 关于页路由壳（手机/平板窄屏 push 进入）
@Component
export struct AboutPage {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('windowW') windowW: number = 0;

  private inset(): number {
    return Bp.contentInset(this.windowW);
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.about_title'), inset: this.inset() })
        AboutContent({ inset: this.inset() })
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
export function AboutBuilder() {
  AboutPage()
}
