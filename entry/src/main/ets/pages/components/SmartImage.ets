import { ImageCache } from '../../common/ImageCache';
import { AppIcon } from './AppIcon';

// 智能图片：源需要请求头时经 ImageCache 管线加载（Referer/UA/Cookie），
// 本地文件与未声明请求头的源保持系统 Image 直连行为
@Component
export struct SmartImage {
  @Prop @Watch('onUrlChanged') url: string = '';
  @Prop sourceKey: string = '';
  @Prop fit: ImageFit = ImageFit.Cover;
  @Prop fill: boolean = true;
  @State display: string = '';
  @State failed: boolean = false;
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

  build() {
    Stack() {
      if (this.display !== '') {
        Image(this.display)
          .width('100%')
          .height(this.fill ? '100%' : 'auto')
          .objectFit(this.fit)
      } else if (this.failed) {
        Column() {
          AppIcon({ name: 'error', iconSize: 20 })
        }
        .width('100%')
        .height(this.fill ? '100%' : 120)
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          LoadingProgress()
            .width(22)
            .height(22)
        }
        .width('100%')
        .height(this.fill ? '100%' : 120)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height(this.fill ? '100%' : 'auto')
  }
}
