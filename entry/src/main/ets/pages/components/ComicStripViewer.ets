import { image } from '@kit.ImageKit';
import { SPage } from '../../model/Models';
import { StripImagePipeline } from '../../common/StripImagePipeline';
import { Theme } from '../../common/Theme';

// 条漫(Webtoon)模式数据源
class StripDataSource implements IDataSource {
  private pages: SPage[] = [];
  private listeners: DataChangeListener[] = [];

  setPages(pages: SPage[]): void {
    this.pages = pages;
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }

  totalCount(): number {
    return this.pages.length;
  }

  getData(index: number): SPage {
    return this.pages[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener): boolean => l !== listener);
  }
}

// 单页条目：经 StripImagePipeline 解码为 PixelMap 后直绘（绕过 Image 网络栈与防盗链拦截）
@Component
struct StripItemView {
  @Prop url: string = '';
  @Prop sourceKey: string = '';
  @Prop isDark: boolean = false;
  @State pixelMap: image.PixelMap | undefined = undefined;
  @State failed: boolean = false;
  @State loading: boolean = false;
  onTap: () => void = () => {};
  private loadToken: number = 0;

  aboutToAppear(): void {
    this.load();
  }

  private load(): void {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.failed = false;
    this.loadToken += 1;
    const token = this.loadToken;
    StripImagePipeline.load(this.url, this.sourceKey).then((pm: image.PixelMap) => {
      if (token !== this.loadToken) {
        return;
      }
      this.pixelMap = pm;
      this.loading = false;
    }).catch((_e: Object) => {
      if (token !== this.loadToken) {
        return;
      }
      this.failed = true;
      this.loading = false;
    });
  }

  build() {
    Column() {
      if (this.pixelMap !== undefined) {
        // 仅约束宽度，高度随图片纵横比自适应
        Image(this.pixelMap)
          .width('100%')
          .objectFit(ImageFit.Contain)
          .interpolation(ImageInterpolation.High)
          .draggable(false)
      } else if (this.loading) {
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(Theme.readerPlaceholder(this.isDark))
          Text($r('app.string.viewer_loading'))
            .fontSize(12)
            .fontColor(Theme.readerPlaceholder(this.isDark))
            .margin({ top: 8 })
        }
        .width('100%')
        .height(320)
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          Text($r('app.string.viewer_load_failed'))
            .fontSize(13)
            .fontColor(Theme.readerPlaceholder(this.isDark))
          Text($r('app.string.viewer_tap_retry'))
            .fontSize(12)
            .fontColor(Theme.readerPlaceholder(this.isDark))
            .margin({ top: 6 })
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .borderRadius(12)
            .border({ width: 1, color: Theme.readerPlaceholder(this.isDark) })
        }
        .width('100%')
        .height(320)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.load();
        })
      }
    }
    .width('100%')
    .onClick(() => {
      this.onTap();
    })
  }
}

// 条漫阅读器：List + LazyForEach 无限竖向滚动，PixelMap 由 StripImagePipeline 提供
// - 初始位置由 initialIndex 指定（续读）
// - onPageVisible 上报当前首可见页，供宿主持久化进度
// - onTap 转发给宿主（切换菜单）
@Component
export struct ComicStripViewer {
  @Prop @Watch('onPagesChanged') pages: SPage[] = [];
  @Prop sourceKey: string = '';
  @Prop initialIndex: number = 0;
  @Prop isDark: boolean = false;
  // 侧边距（百分比 0-25，对齐 Mihon pref_webtoon_side_padding）
  @Prop sidePadding: number = 0;
  scroller: Scroller = new Scroller();
  onTap: () => void = () => {};
  onPageVisible: (index: number) => void = (_i: number) => {};
  private dataSource: StripDataSource = new StripDataSource();
  private lastVisible: number = -1;

  aboutToAppear(): void {
    this.dataSource.setPages(this.pages);
  }

  private onPagesChanged(): void {
    this.dataSource.setPages(this.pages);
    this.lastVisible = -1;
  }

  build() {
    List({ scroller: this.scroller, initialIndex: this.initialIndex }) {
      LazyForEach(this.dataSource, (page: SPage) => {
        ListItem() {
          StripItemView({ url: page.url, sourceKey: this.sourceKey, isDark: this.isDark, onTap: (): void => {
            this.onTap();
          } })
        }
      }, (page: SPage) => `${page.index}:${page.url}`)
    }
    .width('100%')
    .height('100%')
    .padding({ left: `${this.sidePadding}%`, right: `${this.sidePadding}%` })
    .cachedCount(2)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.None)
    .onScrollIndex((first: number, _last: number) => {
      if (first >= 0 && first !== this.lastVisible) {
        this.lastVisible = first;
        this.onPageVisible(first);
      }
    })
  }
}
