// 默认封面占位：无封面条目（本地资源等）与封面缺失场景的统一兜底，
// 主题色板柔和渐变 + 收藏图标，替代纯色底 + photo 图标的单调样式
import { ThemePalette } from '../../common/Theme';
import { AppIcon } from './AppIcon';

@Component
export struct CoverPlaceholder {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @Prop iconSize: number = 30;

  build() {
    Stack() {
      Column() {
        AppIcon({ name: 'collections_bookmark', iconSize: this.iconSize, tint: this.pal.primary })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 160,
      colors: [[this.pal.primarySoft, 0.0], [this.pal.chip, 1.0]]
    })
  }
}
