import { ThemePalette } from '../../common/Theme';
import { PageHeader } from '../components/PageHeader';

// 关于页：logo + 版本 + 开源致谢
@Component
export struct AboutPage {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '关于' })
        Scroll() {
          Column() {
            Image($r('app.media.startIcon'))
              .width(96)
              .height(96)
              .borderRadius(20)
              .margin({ top: 32 })
            Text('MihonHarmony')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.pal.text)
              .margin({ top: 12 })
            Text('版本 1.0.0')
              .fontSize(13)
              .fontColor(this.pal.sub)
              .margin({ top: 4 })

            Column() {
              Text('架构参考 Mihon (Apache-2.0)。在线源以插件形式动态安装，本地源内置。')
                .fontSize(13)
                .fontColor(this.pal.text)
                .lineHeight(20)
              Text('开源致谢：\n· Mihon / Tachiyomi — 应用架构与交互设计 (Apache-2.0)\n· Material Symbols — 应用内图标 (Apache-2.0)\n· MangaDex — 测试用例数据源')
                .fontSize(12)
                .fontColor(this.pal.sub)
                .lineHeight(19)
                .margin({ top: 10 })
            }
            .alignItems(HorizontalAlign.Start)
            .padding(16)
            .backgroundColor(this.pal.card)
            .borderRadius(16)
            .margin({ left: 16, right: 16, top: 24 })
          }
          .width('100%')
          .padding({ bottom: 24 })
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
