import { ImageCache } from '../../common/ImageCache';
import { AppIcon } from './AppIcon';
import { CoverPlaceholder } from './CoverPlaceholder';

// 智能图片：源需要请求头时经 ImageCache 管线加载（Referer/UA/Cookie），
// 本地文件与未声明请求头的源保持系统 Image 直连行为
@Component
export struct SmartImage {
  @Prop @Watch('onUrlChanged') url: string = '';
  @Prop sourceKey: string = '';
  @Prop fit: ImageFit = ImageFit.Cover;
  @Prop fill: boolean = true;
  // 高质量渲染（阅读器设置）：开启时对位图启用高精度插值，放大缩小更平滑但更耗性能
  @Prop highQuality: boolean = false;
  // 无封面时默认封面占位的图标尺寸（小尺寸列表封面传小值）
  @Prop placeholderIconSize: number = 30;
  // 失败态允许点击重试（阅读器页面加载失败时点击重新解析）
  @Prop retryable: boolean = false;
  @State display: string = '';
  @State failed: boolean = false;
  @State imgReady: boolean = false;
  private resolving: string = '';

  aboutToAppear(): void {
    this.resolve();
  }

  @Builder
  failedPlaceholder() {
    Column() {
      AppIcon({ name: 'error', iconSize: 20 })
    }
    .width('100%')
    .height(this.fill ? '100%' : 120)
    .justifyContent(FlexAlign.Center)
    // 优先级单击：宿主（仿真翻页）根节点也挂优先级单击时，子组件优先级手势仍可先识别，保留点按重试
    .priorityGesture(
      TapGesture({ count: 1 })
        .onAction((): void => {
          if (this.retryable) {
            this.retry();
          }
        })
    )
  }

  @Builder
  loadingPlaceholder() {
    Column() {
      LoadingProgress()
        .width(22)
        .height(22)
    }
    .width('100%')
    .height(this.fill ? '100%' : 120)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Stack() {
      if (this.url === '') {
        // 无封面（本地资源等）：显示默认封面占位
        CoverPlaceholder({ iconSize: this.placeholderIconSize })
          .width('100%')
          .height(this.fill ? '100%' : 120)
      } else if (this.display !== '') {
        if (!this.failed) {
          Image(this.display)
            .width('100%')
            .height(this.fill ? '100%' : 'auto')
            .objectFit(this.fit)
            .interpolation(this.highQuality ? ImageInterpolation.High : ImageInterpolation.None)
            .onComplete((): void => {
              this.imgReady = true;
            })
            .onError((): void => {
              this.failed = true;
            })
        }
        if (this.failed) {
          this.failedPlaceholder()
        } else if (!this.imgReady) {
          this.loadingPlaceholder()
        }
      } else if (this.failed) {
        this.failedPlaceholder()
      } else {
        this.loadingPlaceholder()
      }
    }
    .width('100%')
    .height(this.fill ? '100%' : 'auto')
  }

  private onUrlChanged(): void {
    this.resolve();
  }

  // 失败重试：清空解析锁与状态后重新走 resolve（ImageCache 失败不缓存，会重新请求）
  private retry(): void {
    this.resolving = '';
    this.resolve();
  }

  private resolve(): void {
    const u = this.url;
    if (u === '' || u === this.resolving) {
      return;
    }
    this.resolving = u;
    this.display = '';
    this.failed = false;
    this.imgReady = false;
    if (u.indexOf('http://') !== 0 && u.indexOf('https://') !== 0) {
      this.display = u;
      return;
    }
    ImageCache.resolve(u, this.sourceKey).then((p: string) => {
      if (this.resolving === u) {
        this.display = p;
      }
    }).catch((_e: Error) => {
      if (this.resolving === u) {
        this.failed = true;
      }
    });
  }
}
