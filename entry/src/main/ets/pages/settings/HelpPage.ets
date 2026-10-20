// 帮助文档页（应用内自有文档，替代外部 mihon.app 帮助链接）：
// 入门指南 / 书源迁移 / 数据与存储 / 更新与「即将更新」/ 故障排查
import { ThemePalette } from '../../common/Theme';
import { PageHeader } from '../components/PageHeader';

// 帮助文档小节：标题 + 正文（均走资源本地化）
interface HelpSection {
  id: string;
  title: ResourceStr;
  body: ResourceStr;
}

@Component
export struct HelpPage {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  private sections(): HelpSection[] {
    const sections: HelpSection[] = [
      { id: 'getting_started', title: $r('app.string.help_getting_started_title'), body: $r('app.string.help_getting_started_body') },
      { id: 'extensions', title: $r('app.string.help_extensions_title'), body: $r('app.string.help_extensions_body') },
      { id: 'reader', title: $r('app.string.help_reader_title'), body: $r('app.string.help_reader_body') },
      { id: 'downloads', title: $r('app.string.help_downloads_title'), body: $r('app.string.help_downloads_body') },
      { id: 'tracking', title: $r('app.string.help_tracking_title'), body: $r('app.string.help_tracking_body') },
      { id: 'migration', title: $r('app.string.help_migration_title'), body: $r('app.string.help_migration_body') },
      { id: 'updates', title: $r('app.string.help_updates_title'), body: $r('app.string.help_updates_body') },
      { id: 'storage', title: $r('app.string.help_storage_title'), body: $r('app.string.help_storage_body') },
      { id: 'security', title: $r('app.string.help_security_title'), body: $r('app.string.help_security_body') },
      { id: 'troubleshooting', title: $r('app.string.help_troubleshooting_title'), body: $r('app.string.help_troubleshooting_body') }
    ];
    return sections;
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.help_title') })
        Scroll() {
          Column({ space: 12 }) {
            Text($r('app.string.help_intro'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.pal.text)
              .lineHeight(22)
              .padding(16)
              .backgroundColor(this.pal.card)
              .borderRadius(16)
              .width('100%')
              .constraintSize({ maxWidth: 720 })

            ForEach(this.sections(), (section: HelpSection) => {
              Column({ space: 6 }) {
                Text(section.title)
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.pal.text)
                Text(section.body)
                  .fontSize(13)
                  .fontColor(this.pal.sub)
                  .lineHeight(20)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding(16)
              .backgroundColor(this.pal.card)
              .borderRadius(16)
              .constraintSize({ maxWidth: 720 })
            }, (section: HelpSection) => section.id)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: 24 })
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
export function HelpBuilder() {
  HelpPage()
}
