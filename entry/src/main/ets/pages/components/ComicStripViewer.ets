import { image } from '@kit.ImageKit';
import { SPage } from '../../model/Models';
import { StripImagePipeline } from '../../common/StripImagePipeline';
import { Theme } from '../../common/Theme';
import { ReaderTransition } from './ReaderChrome';

// 条漫(List)头部固定条目数（章节过渡页）：真实页 index = List index - STRIP_LEAD_COUNT
export const STRIP_LEAD_COUNT: number = 1;

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
  @Prop pageUrl: string = '';
  @Prop isDark: boolean = false;
  // 图片填充模式：条漫 Contain；连续滚动裁边模式 Cover
  @Prop fit: ImageFit = ImageFit.Contain;
  // 单条目最大高度（0=不限）：连续滚动裁边时钳制为阅读区高度
  @Prop maxItemHeight: number = 0;
  @State pixelMap: image.PixelMap | undefined = undefined;
  @State failed: boolean = false;
  @State loading: boolean = false;
  // 每条目独立捏合缩放（1-3x）与缩放平移（不可命名为 scale：与基类通用属性方法冲突）
  @State zoomScale: number = 1;
  @State offX: number = 0;
  @State offY: number = 0;
  private loadToken: number = 0;
  // 条目销毁标记：回调内校验后再写 @State
  private destroyed: boolean = false;
  private pinchStart: number = 1;
  private panStartX: number = 0;
  private panStartY: number = 0;
  private viewW: number = 0;
  private viewH: number = 0;
  onTap: () => void = () => {
  };

  aboutToAppear(): void {
    this.load();
  }

  // 销毁时仅释放本条目加载过的 url（宿主关闭/切模式/换数据时逐条回收，不清空全局缓存）
  aboutToDisappear(): void {
    this.destroyed = true;
    StripImagePipeline.release(this.url);
  }

  build() {
    Column() {
      if (this.pixelMap !== undefined) {
        Stack() {
          // 仅约束宽度，高度随图片纵横比自适应
          Image(this.pixelMap)
            .width('100%')
            .objectFit(this.fit)
            .interpolation(ImageInterpolation.High)
            .draggable(false)
            .scale({ x: this.zoomScale, y: this.zoomScale })
            .translate({ x: this.offX, y: this.offY })
            .constraintSize({ maxHeight: this.maxItemHeight > 0 ? this.maxItemHeight : 100000 })
            .gesture(GestureGroup(GestureMode.Exclusive,
              PinchGesture()
                .onActionStart((e: PinchGestureEvent) => {
                  this.pinchStart = this.zoomScale;
                })
                .onActionUpdate((e: PinchGestureEvent) => {
                  this.applyScale(this.pinchStart * e.scale);
                })
                .onActionEnd(() => {
                  if (this.zoomScale < 1.05) {
                    this.resetZoom();
                  }
                }),
              TapGesture({ count: 2 })
                .onAction(() => {
                  if (this.zoomScale > 1) {
                    this.resetZoom();
                  } else {
                    this.zoomScale = 2;
                  }
                }),
              TapGesture({ count: 1 })
                .onAction(() => {
                  this.onTap();
                })
            ))
          if (this.zoomScale > 1) {
            // 缩放后覆盖透明层承载平移/捏合，避免 Pan 与 List 滚动手势竞争
            Column()
              .width('100%')
              .height('100%')
              .gesture(GestureGroup(GestureMode.Exclusive,
                PanGesture()
                  .onActionStart((e: PanGestureEvent) => {
                    this.panStartX = this.offX;
                    this.panStartY = this.offY;
                  })
                  .onActionUpdate((e: PanGestureEvent) => {
                    this.applyPan(this.panStartX + e.offsetX, this.panStartY + e.offsetY);
                  }),
                PinchGesture()
                  .onActionStart((e: PinchGestureEvent) => {
                    this.pinchStart = this.zoomScale;
                  })
                  .onActionUpdate((e: PinchGestureEvent) => {
                    this.applyScale(this.pinchStart * e.scale);
                  })
                  .onActionEnd(() => {
                    if (this.zoomScale < 1.05) {
                      this.resetZoom();
                    }
                  }),
                TapGesture({ count: 1 })
                  .onAction(() => {
                    this.onTap();
                  })
              ))
          }
        }
        .width('100%')
        .onAreaChange((_o: Area, n: Area) => {
          this.viewW = Number(n.width);
          this.viewH = Number(n.height);
        })
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
        .onClick(() => {
          this.onTap();
        })
      } else {
        Column() {
          Text($r('app.string.viewer_load_failed'))
            .fontSize(13)
            .fontColor(Theme.readerPlaceholder(this.isDark))
          Text($r('app.string.viewer_tap_retry'))
            .fontSize(12)
            .fontColor(Theme.readerPlaceholder(this.isDark))
            .margin({ top: 6 })
            .padding({
              left: 12,
              right: 12,
              top: 4,
              bottom: 4
            })
            .borderRadius(12)
            .border({ width: 1, color: Theme.readerPlaceholder(this.isDark) })
        }
        .width('100%')
        .height(320)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.load();
          this.onTap();
        })
      }
    }
    .width('100%')
  }

  private applyScale(v: number): void {
    const s = Math.min(3, Math.max(1, v));
    this.zoomScale = s;
    if (s <= 1) {
      this.offX = 0;
      this.offY = 0;
    } else {
      this.applyPan(this.offX, this.offY);
    }
  }

  private applyPan(x: number, y: number): void {
    const maxX = (this.zoomScale - 1) * this.viewW / 2;
    const maxY = (this.zoomScale - 1) * this.viewH / 2;
    this.offX = Math.min(maxX, Math.max(-maxX, x));
    this.offY = Math.min(maxY, Math.max(-maxY, y));
  }

  private resetZoom(): void {
    this.zoomScale = 1;
    this.offX = 0;
    this.offY = 0;
  }

  private load(): void {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.failed = false;
    this.loadToken += 1;
    const token = this.loadToken;
    StripImagePipeline.load(this.url, this.sourceKey, this.pageUrl).then((pm: image.PixelMap) => {
      if (this.destroyed || token !== this.loadToken) {
        return;
      }
      this.pixelMap = pm;
      this.loading = false;
    }).catch((_e: Object) => {
      if (this.destroyed || token !== this.loadToken) {
        return;
      }
      this.failed = true;
      this.loading = false;
    });
  }
}

// 条漫阅读器：List + LazyForEach 无限竖向滚动，PixelMap 由 StripImagePipeline 提供
// - 初始位置由 initialIndex 指定（续读，含头部过渡页偏移）
// - 列表头部/尾部为章节过渡页（上一章/下一章，对齐 Mihon WebtoonViewer）
// - onPageVisible 上报当前首可见 List 下标（含过渡页下标），供宿主持久化进度
// - onTap 转发给宿主（切换菜单）；过渡页点击进入相邻章节（无目标时回落为 onTap）
@Component
export struct ComicStripViewer {
  @Prop @Watch('onPagesChanged') pages: SPage[] = [];
  @Prop sourceKey: string = '';
  @Prop initialIndex: number = 0;
  @Prop isDark: boolean = false;
  // 侧边距（百分比 0-25，对齐 Mihon pref_webtoon_side_padding）
  @Prop sidePadding: number = 0;
  // 章节过渡页信息（当前章名 + 相邻章名，空串表示无相邻章节）
  @Prop currentChapterName: string = '';
  @Prop prevChapterName: string = '';
  @Prop nextChapterName: string = '';
  // 过渡页文字配色（宿主按阅读背景推导）
  @Prop textCol: string = '#ECEEF2';
  @Prop subCol: string = '#99ECEEF2';
  // 条目间距（vp，条漫/连续模式页间距）
  @Prop gap: number = 0;
  // 图片填充模式（连续滚动裁边传 Cover，默认条漫 Contain）
  @Prop fit: ImageFit = ImageFit.Contain;
  // 单条目最大高度（0=不限；连续滚动裁边传阅读区高度）
  @Prop maxItemHeight: number = 0;
  scroller: Scroller = new Scroller();
  private dataSource: StripDataSource = new StripDataSource();
  private lastVisible: number = -1;
  onTap: () => void = () => {
  };
  onPageVisible: (index: number) => void = (_i: number) => {
  };
  onPrevChapter: () => void = () => {
  };
  onNextChapter: () => void = () => {
  };

  aboutToAppear(): void {
    this.dataSource.setPages(this.pages);
  }

  build() {
    List({ scroller: this.scroller, initialIndex: this.initialIndex, space: this.gap }) {
      // 头部：上一章过渡页
      ListItem() {
        Column() {
          ReaderTransition({
            kind: 'prev',
            currentName: this.currentChapterName,
            targetName: this.prevChapterName,
            textCol: this.textCol,
            subCol: this.subCol
          })
        }
        .width('100%')
        .constraintSize({ minHeight: 320 })
        .justifyContent(FlexAlign.Center)
        .padding({ top: 48, bottom: 24 })
        .onClick(() => {
          if (this.prevChapterName !== '') {
            this.onPrevChapter();
          } else {
            this.onTap();
          }
        })
      }

      LazyForEach(this.dataSource, (page: SPage) => {
        ListItem() {
          StripItemView({
            url: page.url,
            sourceKey: this.sourceKey,
            pageUrl: page.pageUrl ?? '',
            isDark: this.isDark,
            fit: this.fit,
            maxItemHeight: this.maxItemHeight,
            onTap: (): void => {
              this.onTap();
            }
          })
        }
      }, (page: SPage) => `${page.index}:${page.url}`)
      // 尾部：下一章过渡页
      ListItem() {
        Column() {
          ReaderTransition({
            kind: 'next',
            currentName: this.currentChapterName,
            targetName: this.nextChapterName,
            textCol: this.textCol,
            subCol: this.subCol
          })
        }
        .width('100%')
        .constraintSize({ minHeight: 320 })
        .justifyContent(FlexAlign.Center)
        .padding({ top: 24, bottom: 48 })
        .onClick(() => {
          if (this.nextChapterName !== '') {
            this.onNextChapter();
          } else {
            this.onTap();
          }
        })
      }
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

  private onPagesChanged(): void {
    this.dataSource.setPages(this.pages);
    this.lastVisible = -1;
    // 换数据后重新定位到宿主指定的起始页
    this.scroller.scrollToIndex(this.initialIndex);
  }
}
