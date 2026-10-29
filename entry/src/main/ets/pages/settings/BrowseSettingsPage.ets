import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { NavGlassPage } from '../../common/HdsNavHost';
import { PrefGroup, PrefSwitchRow } from '../components/Prefs';

// 浏览设置内容：NSFW 源显示 + 扩展更新检查
@Component
export struct BrowseSettingsContent {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  // 可更新扩展数量徽标（PluginService.checkExtensionUpdates 刷新仓库索引后写入）
  @StorageProp('extUpdateCount') extUpdateCount: number = 0;

  build() {
    Scroll() {
      Column() {
        PrefGroup({ groupTitle: $r('app.string.browse_set_content') }) {
          PrefSwitchRow({
            title: $r('app.string.browse_set_show_nsfw'),
            initValue: Settings.getShowNsfw(),
            apply: (value: boolean): void => {
              Settings.setShowNsfw(value);
            }
          })
        }

        // 扩展更新检查（对齐 Mihon Extension updates）：刷新插件仓库索引时
        // 比对已装插件版本，有更新时发本地通知提醒（24 小时内不重复）
        PrefGroup({ groupTitle: '扩展更新' }) {
          PrefSwitchRow({
            title: '检查扩展更新',
            subtitle: this.extUpdateCount > 0 ?
              `有 ${this.extUpdateCount} 个扩展可更新` : '刷新插件仓库时检查扩展更新并提醒',
            initValue: Settings.getExtensionUpdateCheck(),
            apply: (value: boolean): void => {
              Settings.setExtensionUpdateCheck(value);
            }
          })
        }

        Text($r('app.string.browse_set_nsfw_hint'))
          .fontSize(12)
          .fontColor(this.pal.sub)
          .margin({ left: 20, top: 8 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 24 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
  }
}

// 浏览设置路由壳（手机/平板窄屏 push 进入）
@Component
export struct BrowseSettingsPage {
  build() {
    NavGlassPage({ title: $r('app.string.browse_set_title') }) {
      Column() {
        BrowseSettingsContent()
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function BrowseSettingsBuilder() {
  BrowseSettingsPage()
}
