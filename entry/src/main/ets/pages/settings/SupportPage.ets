import { common } from '@kit.AbilityKit';
import { ThemePalette } from '../../common/Theme';
import { Util } from '../../common/Util';
import { PageHeader } from '../components/PageHeader';
import { PrefGroup, IconRow } from '../components/Prefs';

const DONATE_PATREON_URL: string = 'https://patreon.com/mihon/membership';
const DONATE_OPENCOLLECTIVE_URL: string = 'https://opencollective.com/mihon/contribute';
const DISCORD_URL: string = 'https://discord.gg/mihon';

// 支持我们（对齐 Mihon SupportUsScreen）：
// 赞助渠道（Patreon / OpenCollective）+ 赞助者致谢 + 联系渠道（Discord）
@Component
export struct SupportPage {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  private openLink(url: string): void {
    const context = getContext(this) as common.UIAbilityContext;
    Util.openUrl(context, url);
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.more_support') })
        Scroll() {
          Column({ space: 12 }) {
            Text($r('app.string.support_perks'))
              .fontSize(12)
              .fontColor(this.pal.sub)
              .margin({ left: 20 })
              .constraintSize({ maxWidth: 680 })

            // 赞助渠道
            PrefGroup() {
              IconRow({
                title: $r('app.string.support_patreon'),
                icon: 'patreon',
                onTap: (): void => {
                  this.openLink(DONATE_PATREON_URL);
                }
              })
              Divider().color(this.pal.divider).margin({ left: 52 })
              IconRow({
                title: $r('app.string.support_opencollective'),
                icon: 'opencollective',
                onTap: (): void => {
                  this.openLink(DONATE_OPENCOLLECTIVE_URL);
                }
              })
            }

            // 致谢与联系说明
            Text($r('app.string.support_supported_by', 200))
              .fontSize(12)
              .fontColor(this.pal.sub)
              .margin({ left: 20, right: 20 })
              .constraintSize({ maxWidth: 680 })
            Text($r('app.string.support_contact_msg'))
              .fontSize(12)
              .fontColor(this.pal.sub)
              .margin({ left: 20 })
              .constraintSize({ maxWidth: 680 })

            // 联系渠道
            PrefGroup() {
              IconRow({
                title: $r('app.string.support_discord'),
                icon: 'discord',
                onTap: (): void => {
                  this.openLink(DISCORD_URL);
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

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function SupportBuilder() {
  SupportPage()
}
