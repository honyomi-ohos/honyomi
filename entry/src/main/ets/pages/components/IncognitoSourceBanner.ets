import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { PluginRepo } from '../../data/Repos';
import { AppIcon } from './AppIcon';

// 按插件隐身浏览提示条（对齐 Mihon IncognitoBanner）：
// 浏览源页面进入时，当前 sourceKey 所属插件被「按插件隐身」
// （Settings.isPluginIncognito）则在页面顶部展示「无痕浏览中」提示条。
// 判定走 PluginRepo.pluginKeyOfSource（sourceKey → pluginKey 缓存查询）；
// 本组件不持有状态存储，仅读中心化配置（无痕闸门见 HistoryRepo.isIncognitoFor）
@Component
export struct IncognitoSourceBanner {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @Prop @Watch('onSourceKeyChanged') sourceKey: string = '';
  @State incognitoOn: boolean = false;

  aboutToAppear(): void {
    this.refreshIncognito();
  }

  // 页面复用/源切换（sourceKey 变化）时重查隐身状态
  onSourceKeyChanged(): void {
    this.refreshIncognito();
  }

  build() {
    if (this.incognitoOn) {
      Row({ space: 6 }) {
        AppIcon({ name: 'visibility_off', iconSize: 14, tint: this.pal.sub })
        Text('无痕浏览中 · 不记录阅读历史与统计')
          .fontSize(12)
          .fontColor(this.pal.sub)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .padding({ top: 6, bottom: 6 })
      .backgroundColor(this.pal.chip)
      .borderRadius(10)
    }
  }

  private refreshIncognito(): void {
    if (this.sourceKey === '') {
      this.incognitoOn = false;
      return;
    }
    PluginRepo.pluginKeyOfSource(this.sourceKey).then((pluginKey: string): void => {
      this.incognitoOn = Settings.isPluginIncognito(pluginKey);
    }).catch((_e: Error): void => {
      this.incognitoOn = false;
    });
  }
}
