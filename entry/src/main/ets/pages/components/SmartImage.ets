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
  // 无封面时默认封面占位的图标尺寸（小尺寸列表封面传小值）
  @Prop placeholderIconSize: number = 30;
  @State display: string = '';
  @State failed: boolean = false;
  @State imgReady: boolean = false;
  private resolving: string = '';

  aboutToAppear(): void {
    this.resolve();
  }

  private onUrlChanged(): void {
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

  @Builder
  failedPlaceholder() {
    Column() {
      AppIcon({ name: 'error', iconSize: 20 })
    }
    .width('100%')
    .height(this.fill ? '100%' : 120)
    .justifyContent(FlexAlign.Center)
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
}
