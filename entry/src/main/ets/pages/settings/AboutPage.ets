import { ThemePalette } from '../../common/Theme';
import { Util } from '../../common/Util';
import { PageHeader } from '../components/PageHeader';

// 开源致谢单条目：组件名 + 说明（由 about_ack 按「· 名称 — 说明」拆分）
interface AckItem {
  name: string;
  detail: string;
}

// 关于页内容：logo + 版本徽章 + 简介卡片 + 开源致谢卡片
@Component
export struct AboutContent {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State ackTitle: string = '';
  @State ackItems: AckItem[] = [];

  aboutToAppear(): void {
    try {
      const raw: string = Util.resStr(this.getUIContext(), $r('app.string.about_ack'));
      const lines: string[] = raw.split('\n');
      const items: AckItem[] = [];
      for (let i = 0; i < lines.length; i++) {
        const line: string = lines[i].trim();
        if (line.length === 0) {
          continue;
        }
        if (i === 0) {
          // 标题行：去掉结尾冒号（中英文）作为卡片标题
          this.ackTitle = line.replace(/[：:]\s*$/, '');
        } else {
          // 条目行：去掉「· 」前缀，按「 — 」拆出名称与说明
          const entry: string = line.startsWith('· ') ? line.substring(2) : line;
          const sepIdx: number = entry.indexOf(' — ');
          if (sepIdx >= 0) {
            items.push({ name: entry.substring(0, sepIdx), detail: entry.substring(sepIdx + 3) });
          } else {
            items.push({ name: entry, detail: '' });
          }
        }
      }
      this.ackItems = items;
    } catch (error) {
      this.ackTitle = '';
      this.ackItems = [];
    }
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
        Text($r('app.string.about_version'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal.onPrimarySoft)
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
          .backgroundColor(this.pal.primarySoft)
          .borderRadius(999)
          .margin({ top: 10 })

        Column() {
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

          if (this.ackTitle.length > 0) {
            Column() {
              Text(this.ackTitle)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.pal.text)
                .lineHeight(20)
              ForEach(this.ackItems, (item: AckItem) => {
                Row() {
                  Column()
                    .width(5)
                    .height(5)
                    .borderRadius(2.5)
                    .backgroundColor(this.pal.primary)
                    .margin({ top: 6 })
                  Column() {
                    Text(item.name)
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.pal.text)
                      .lineHeight(18)
                    if (item.detail.length > 0) {
                      Text(item.detail)
                        .fontSize(12)
                        .fontColor(this.pal.sub)
                        .lineHeight(17)
                        .margin({ top: 2 })
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 10 })
                }
                .alignItems(VerticalAlign.Top)
                .width('100%')
                .margin({ top: 10 })
              }, (item: AckItem) => item.name)
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(16)
            .backgroundColor(this.pal.card)
            .borderRadius(16)
            .margin({ top: 12 })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
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
}

// 关于页路由壳（手机/平板窄屏 push 进入）
@Component
export struct AboutPage {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.about_title') })
        AboutContent()
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
