import { MangaRecord } from '../../model/Models';
import { ThemePalette } from '../../common/Theme';
import { AppIcon } from './AppIcon';
import { LibraryMangaItem } from './LibraryItems';

// 拖动位移上限（vp）：超过后截断，避免卡片拖出过远
const SWIPE_MAX_DRAG: number = 96;
// 松手触发阈值（vp）：位移超过该值执行动作，否则回弹
const SWIPE_TRIGGER: number = 48;

// 书架条目滑动动作包装（对齐 Mihon 书架 Swipe actions）：
// 向右滑露出起始端动作（卡片左侧提示区），向左滑露出末端动作（卡片右侧提示区）。
// 拖动时卡片跟随手指位移（视觉反馈），松手超过阈值执行动作并回弹，否则直接回弹。
// 动作当前支持 'read'（切换已读/未读）与 'none'（该方向禁用拖动）。
@Component
export struct SwipeActionItem {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @ObjectLink record: MangaRecord;
  @Prop mode: string = 'compact';
  // 起始端 / 末端滑动动作：'read' | 'none'
  @Prop startAction: string = 'none';
  @Prop endAction: string = 'none';
  @Prop unreadCount: number = 0;
  @Prop downloadCount: number = 0;
  @Prop langLabel: string = '';
  @Prop isLocal: boolean = false;
  @Prop showUnreadBadge: boolean = true;
  @Prop showDownloadBadge: boolean = true;
  @Prop showLocalBadge: boolean = false;
  @Prop showLanguageBadge: boolean = false;
  @Prop isSelected: boolean = false;
  // 松手触发动作时回调（'read' 等，'none' 不会回调）
  onSwipe: (action: string) => void = (_action: string) => {
  };
  // 卡片当前水平位移（拖动跟随，松手动画归零）
  @State dragOffset: number = 0;
  // 卡片实测高度：提示区按此高度撑满。
  // 不能用 height('100%')——GridItem/ListItem 行高自适应时，百分比按父级测量约束
  // （Grid 视口高）解析，会把每个条目撑到整屏高，书架一屏只剩一行
  @State cardH: number = 0;
  onItemClick: (record: MangaRecord) => void = (_r: MangaRecord) => {
  };
  onItemLongPress: (record: MangaRecord) => void = (_r: MangaRecord) => {
  };
  onItemMenuSelect: (record: MangaRecord) => void = (_r: MangaRecord) => {
  };
  onItemMenuCategory: (record: MangaRecord) => void = (_r: MangaRecord) => {
  };

  build() {
    Stack() {
      // 起始端动作提示（右滑时从卡片左侧露出）
      if (this.startAction !== 'none') {
        Row() {
          AppIcon({ name: 'done_all', iconSize: 22, tint: this.pal.onPrimary })
        }
        .width('100%')
        .height(this.cardH)
        .justifyContent(FlexAlign.Start)
        .padding({ left: 20 })
        .backgroundColor(this.pal.primary)
        .borderRadius(4)
        .clip(true)
        .opacity(this.startHintOpacity())
      }
      // 末端动作提示（左滑时从卡片右侧露出）
      if (this.endAction !== 'none') {
        Row() {
          AppIcon({ name: 'done_all', iconSize: 22, tint: this.pal.onPrimary })
        }
        .width('100%')
        .height(this.cardH)
        .justifyContent(FlexAlign.End)
        .padding({ right: 20 })
        .backgroundColor(this.pal.primary)
        .borderRadius(4)
        .clip(true)
        .opacity(this.endHintOpacity())
      }
      // 卡片内容：跟随手指水平位移，松手执行或回弹
      Column() {
        LibraryMangaItem({
          record: this.record,
          mode: this.mode,
          unreadCount: this.unreadCount,
          downloadCount: this.downloadCount,
          langLabel: this.langLabel,
          isLocal: this.isLocal,
          showUnreadBadge: this.showUnreadBadge,
          showDownloadBadge: this.showDownloadBadge,
          showLocalBadge: this.showLocalBadge,
          showLanguageBadge: this.showLanguageBadge,
          isSelected: this.isSelected,
          onItemClick: (r: MangaRecord): void => {
            this.onItemClick(r);
          },
          onItemLongPress: (r: MangaRecord): void => {
            this.onItemLongPress(r);
          },
          onItemMenuSelect: (r: MangaRecord): void => {
            this.onItemMenuSelect(r);
          },
          onItemMenuCategory: (r: MangaRecord): void => {
            this.onItemMenuCategory(r);
          }
        })
      }
      .width('100%')
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        const h: number = typeof newArea.height === 'number' ? newArea.height : 0;
        if (h > 0 && Math.abs(h - this.cardH) > 0.5) {
          this.cardH = h;
        }
      })
      .translate({ x: this.dragOffset })
      .gesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 8 })
          .onActionUpdate((event: GestureEvent) => {
            this.applyDrag(event.offsetX);
          })
          .onActionEnd(() => {
            this.finishDrag();
          })
          .onActionCancel(() => {
            this.resetDrag();
          })
      )
    }
    .width('100%')
  }

  // 拖动跟随：按动作配置单侧截断（无动作方向不可拖），并限制最大位移
  private applyDrag(offsetX: number): void {
    let x = offsetX;
    if (x > 0 && this.startAction === 'none') {
      x = 0;
    }
    if (x < 0 && this.endAction === 'none') {
      x = 0;
    }
    if (x > SWIPE_MAX_DRAG) {
      x = SWIPE_MAX_DRAG;
    }
    if (x < -SWIPE_MAX_DRAG) {
      x = -SWIPE_MAX_DRAG;
    }
    this.dragOffset = x;
  }

  // 松手：超过阈值执行对应方向动作（回弹动画后触发），否则仅回弹
  private finishDrag(): void {
    const x = this.dragOffset;
    this.resetDrag();
    if (x >= SWIPE_TRIGGER && this.startAction !== 'none') {
      this.onSwipe(this.startAction);
    } else if (x <= -SWIPE_TRIGGER && this.endAction !== 'none') {
      this.onSwipe(this.endAction);
    }
  }

  // 回弹动画：位移动画归零
  private resetDrag(): void {
    this.getUIContext().animateTo({ duration: 200, curve: Curve.Friction }, (): void => {
      this.dragOffset = 0;
    });
  }

  // 提示区透明度随位移渐显（接近阈值时完全不透明）
  private startHintOpacity(): number {
    if (this.dragOffset <= 0) {
      return 0;
    }
    return Math.min(1, this.dragOffset / SWIPE_TRIGGER);
  }

  private endHintOpacity(): number {
    if (this.dragOffset >= 0) {
      return 0;
    }
    return Math.min(1, -this.dragOffset / SWIPE_TRIGGER);
  }
}
