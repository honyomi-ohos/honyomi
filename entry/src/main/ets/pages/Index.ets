import { Theme } from '../common/Theme';
import { LibraryPage } from './LibraryPage';
import { UpdatesPage } from './UpdatesPage';
import { HistoryPage } from './HistoryPage';
import { BrowsePage } from './BrowsePage';
import { MorePage } from './MorePage';
import { MangaDetailPage } from './MangaDetailPage';
import { ReaderPage } from './ReaderPage';

@Entry
@Component
struct Index {
  @Provide('navStack') pathStack: NavPathStack = new NavPathStack();
  @State currentTab: number = 0;
  @StorageProp('isDark') isDark: boolean = false;

  @Builder
  pageMap(name: string) {
    if (name === 'MangaDetail') {
      MangaDetailPage()
    } else if (name === 'Reader') {
      ReaderPage()
    }
  }

  @Builder
  tabBuilder(title: string, index: number) {
    Column() {
      Text(title)
        .fontSize(14)
        .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentTab === index ? Theme.primary(this.isDark) : Theme.sub(this.isDark))
    }
    .justifyContent(FlexAlign.Center)
    .height('100%')
  }

  build() {
    Navigation(this.pathStack) {
      Tabs({ barPosition: BarPosition.End }) {
        TabContent() {
          LibraryPage()
        }
        .tabBar(this.tabBuilder('书架', 0))

        TabContent() {
          UpdatesPage()
        }
        .tabBar(this.tabBuilder('更新', 1))

        TabContent() {
          HistoryPage()
        }
        .tabBar(this.tabBuilder('历史', 2))

        TabContent() {
          BrowsePage()
        }
        .tabBar(this.tabBuilder('浏览', 3))

        TabContent() {
          MorePage()
        }
        .tabBar(this.tabBuilder('更多', 4))
      }
      .scrollable(true)
      .barMode(BarMode.Fixed)
      .onChange((index: number) => {
        this.currentTab = index;
      })
    }
    .navDestination(this.pageMap)
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .backgroundColor(Theme.bg(this.isDark))
  }
}
