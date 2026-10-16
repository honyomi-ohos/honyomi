import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { Bp } from '../../common/Breakpoint';
import { PageHeader } from '../components/PageHeader';
import { IconRow, PrefGroup, PrefSelectRow } from '../components/Prefs';
import { AppIcon } from '../components/AppIcon';
import { AppearanceContent } from './AppearancePage';
import { LibrarySettingsContent } from './LibrarySettingsPage';
import { ReaderSettingsContent } from './ReaderSettingsPage';
import { PlayerSettingsContent } from './PlayerSettingsPage';
import { DownloadsSettingsContent } from './DownloadsSettingsPage';
import { BrowseSettingsContent } from './BrowseSettingsPage';
import { DataStorageContent } from './DataStoragePage';
import { TrackingContent } from './TrackingPage';
import { PrivacyContent } from './PrivacyPage';
import { AdvancedContent } from './AdvancedPage';
import { AboutContent } from './AboutPage';
import { LanguageContent } from './LanguagePage';
import { OnboardingParams } from '../../model/RouteParams';
import { LimitedBody } from '../components/LimitedBody';

// lg 双栏左栏分类（index 与 CAT_ICONS、catTitle() 一一对应）
const CAT_ICONS: string[] = [
  'tune', 'palette', 'collections_bookmark', 'image', 'play_arrow',
  'download', 'explore', 'sync', 'storage', 'lock', 'settings', 'info'
];
// 分类索引：0 常规 / 1 外观 / 2 书库 / 3 阅读器 / 4 播放器 / 5 下载 / 6 浏览
// / 7 追踪 / 8 数据与存储 / 9 隐私 / 10 高级 / 11 关于
const CAT_DEFAULT: number = 1;

// 设置中心主页：sm/md 为「常规 + 各分类入口」列表；lg(≥840vp) 双栏
// （左侧分类导航 + 右侧内容面板，对齐系统设置布局；二级页如语言在右栏内切换）
@Component
export struct SettingsPage {
  // 路由栈：NavDestination onReady 时从自身上下文获取（官方推荐方式）
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('windowW') windowW: number = 0;
  @StorageProp('statusBarH') statusBarH: number = 0;
  @State selCat: number = CAT_DEFAULT;
  // 右栏二级页：'' 分类内容本身；'Language' 外观分类内的语言选择
  @State rightSub: string = '';

  @Builder
  railItem(index: number) {
    Row({ space: 12 }) {
      AppIcon({
        name: CAT_ICONS[index],
        iconSize: 22,
        tint: this.selCat === index ? this.pal.primary : this.pal.sub
      })
      Text(this.catTitle(index))
        .fontSize(15)
        .fontWeight(this.selCat === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.selCat === index ? this.pal.primary : this.pal.text)
        .layoutWeight(1)
        .maxLines(1)
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 12 })
    .borderRadius(12)
    .backgroundColor(this.selCat === index ? this.pal.chip : Color.Transparent)
    .onClick(() => {
      this.selCat = index;
      this.rightSub = '';
    })
  }

  // ---- lg 双栏：左栏分类导航 ----

  // 标题（左栏已高亮当前分类，重复显示冗余），顶部由外层补少量内边距
  @Builder
  paneHeader() {
    if (this.rightSub === 'Language') {
      Row({ space: 8 }) {
        AppIcon({ name: 'arrow_back', iconSize: 20, tint: this.pal.text })
          .onClick(() => {
            this.rightSub = '';
          })
        Text($r('app.string.appearance_language'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal.text)
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 10,
        bottom: 6
      })
    }
  }

  // ---- lg 双栏：右栏 ----

  // lg 双栏右栏头：仅二级页（语言）保留返回键 + 标题；分类内容不重复分类

  // 常规分类内容（仅 lg 双栏右栏使用；窄屏展示在主页列表顶部）
  @Builder
  generalPane() {
    Scroll() {
      Column() {
        PrefGroup({ groupTitle: $r('app.string.settings_general') }) {
          PrefSelectRow({
            title: $r('app.string.settings_start_tab'),
            options: [
              $r('app.string.settings_tab_library'),
              $r('app.string.settings_tab_updates'),
              $r('app.string.settings_tab_history'),
              $r('app.string.settings_tab_browse'),
              $r('app.string.settings_tab_more')
            ],
            selectedIndex: Settings.getStartTab(),
            onSelectIndex: (index: number): void => {
              Settings.setStartTab(index);
            }
          })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 24 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
  }

  // + 右内容面板（自行避开状态栏）；标题不再通栏压在双栏之上，避免分割线顶端缺一段
  @Builder
  wideBody() {
    Row() {
      Column() {
        PageHeader({ title: $r('app.string.settings_title') })
        Scroll() {
          Column({ space: 4 }) {
            ForEach(CAT_ICONS, (icon: string, index: number) => {
              this.railItem(index)
            }, (icon: string, index: number) => `cat-${index}`)
          }
          .width('100%')
          .padding({
            left: 12,
            right: 12,
            top: 8,
            bottom: 8
          })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .align(Alignment.TopStart)
      }
      .width(264)
      .height('100%')

      Divider()
        .vertical(true)
        .height('100%')
        .color(this.pal.divider)

      // 右栏限宽居中：平板横屏/PC 宽窗口下设置面板保持可读宽度
      Column() {
        LimitedBody() {
          Column() {
            this.paneHeader()
            if (this.rightSub === 'Language') {
              LanguageContent()
                .layoutWeight(1)
            } else if (this.selCat === 0) {
              this.generalPane()
            } else if (this.selCat === 1) {
              AppearanceContent({
                onNavigate: (route: string): void => {
                  this.rightSub = route === 'Language' ? 'Language' : '';
                }
              })
                .layoutWeight(1)
            } else if (this.selCat === 2) {
              LibrarySettingsContent()
                .layoutWeight(1)
            } else if (this.selCat === 3) {
              ReaderSettingsContent()
                .layoutWeight(1)
            } else if (this.selCat === 4) {
              PlayerSettingsContent()
                .layoutWeight(1)
            } else if (this.selCat === 5) {
              DownloadsSettingsContent()
                .layoutWeight(1)
            } else if (this.selCat === 6) {
              BrowseSettingsContent()
                .layoutWeight(1)
            } else if (this.selCat === 7) {
              TrackingContent()
                .layoutWeight(1)
            } else if (this.selCat === 8) {
              DataStorageContent()
                .layoutWeight(1)
            } else if (this.selCat === 9) {
              PrivacyContent()
                .layoutWeight(1)
            } else if (this.selCat === 10) {
              AdvancedContent({
                onOpenOnboarding: (): void => {
                  const params: OnboardingParams = { firstRun: false };
                  this.pathStack.pushPathByName('Onboarding', params);
                }
              })
                .layoutWeight(1)
            } else {
              AboutContent()
                .layoutWeight(1)
            }
          }
          .width('100%')
          .height('100%')
          // 分类内容无右栏头时补顶部内边距（二级页头部自带间距则不补）
          .padding({ top: this.rightSub === '' ? 8 : 0 })
        }
      }
      .layoutWeight(1)
      .height('100%')
      // 分割线通到窗口顶端后右栏从顶部铺满，自行避开状态栏
      .padding({ top: this.statusBarH })
    }
    .width('100%')
    .layoutWeight(1)
  }

  // lg 双栏主体：左分类导航（顶部自带「设置」标题）+ 竖分割线（通到窗口顶端）

  // 窄屏（sm/md）分类入口列表
  @Builder
  compactList() {
    Scroll() {
      Column({ space: 12 }) {
        PrefGroup({ groupTitle: $r('app.string.settings_general') }) {
          PrefSelectRow({
            title: $r('app.string.settings_start_tab'),
            options: [
              $r('app.string.settings_tab_library'),
              $r('app.string.settings_tab_updates'),
              $r('app.string.settings_tab_history'),
              $r('app.string.settings_tab_browse'),
              $r('app.string.settings_tab_more')
            ],
            selectedIndex: Settings.getStartTab(),
            onSelectIndex: (index: number): void => {
              Settings.setStartTab(index);
            }
          })
        }

        PrefGroup({ groupTitle: $r('app.string.settings_personalization') }) {
          IconRow({
            title: $r('app.string.appearance_title'),
            icon: 'palette',
            onTap: (): void => {
              this.pathStack.pushPathByName('Appearance', null);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          IconRow({
            title: $r('app.string.settings_library'),
            icon: 'collections_bookmark',
            onTap: (): void => {
              this.pathStack.pushPathByName('LibrarySettings', null);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          IconRow({
            title: $r('app.string.settings_reader'),
            icon: 'image',
            onTap: (): void => {
              this.pathStack.pushPathByName('ReaderSettings', null);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          IconRow({
            title: $r('app.string.player_set_title'),
            icon: 'play_arrow',
            onTap: (): void => {
              this.pathStack.pushPathByName('PlayerSettings', null);
            }
          })
        }

        PrefGroup({ groupTitle: $r('app.string.settings_data') }) {
          IconRow({
            title: $r('app.string.settings_downloads'),
            icon: 'download',
            onTap: (): void => {
              this.pathStack.pushPathByName('DownloadsSettings', null);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          IconRow({
            title: $r('app.string.settings_browse'),
            icon: 'explore',
            onTap: (): void => {
              this.pathStack.pushPathByName('BrowseSettings', null);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          IconRow({
            title: $r('app.string.track_title'),
            icon: 'sync',
            onTap: (): void => {
              this.pathStack.pushPathByName('Tracking', null);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          IconRow({
            title: $r('app.string.data_storage_title'),
            icon: 'storage',
            onTap: (): void => {
              this.pathStack.pushPathByName('DataStorage', null);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          IconRow({
            title: $r('app.string.privacy_title'),
            icon: 'lock',
            onTap: (): void => {
              this.pathStack.pushPathByName('Privacy', null);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          IconRow({
            title: $r('app.string.settings_advanced'),
            icon: 'settings',
            onTap: (): void => {
              this.pathStack.pushPathByName('Advanced', null);
            }
          })
        }

        PrefGroup({ groupTitle: $r('app.string.appearance_other') }) {
          IconRow({
            title: $r('app.string.settings_about'),
            icon: 'info',
            onTap: (): void => {
              this.pathStack.pushPathByName('About', null);
            }
          })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 24 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
  }

  build() {
    NavDestination() {
      Column() {
        if (Bp.isWide(this.windowW)) {
          this.wideBody()
        } else {
          PageHeader({ title: $r('app.string.settings_title') })
          this.compactList()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal.bg)
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
    })
    .backgroundColor(this.pal.bg)
  }

  private catTitle(index: number): ResourceStr {
    switch (index) {
      case 0:
        return $r('app.string.settings_general');
      case 1:
        return $r('app.string.appearance_title');
      case 2:
        return $r('app.string.settings_library');
      case 3:
        return $r('app.string.settings_reader');
      case 4:
        return $r('app.string.player_set_title');
      case 5:
        return $r('app.string.settings_downloads');
      case 6:
        return $r('app.string.settings_browse');
      case 7:
        return $r('app.string.track_title');
      case 8:
        return $r('app.string.data_storage_title');
      case 9:
        return $r('app.string.privacy_title');
      case 10:
        return $r('app.string.settings_advanced');
      default:
        return $r('app.string.settings_about');
    }
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function SettingsBuilder() {
  SettingsPage()
}
