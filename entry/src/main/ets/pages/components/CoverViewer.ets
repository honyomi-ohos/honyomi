// 封面查看器（对齐 Mihon MangaCoverDialog）：
// 点击封面进入全屏查看，底部左侧关闭、右侧分享/保存/编辑封面；
// 支持双击缩放、捏合缩放与平移，点击图片关闭；
// 兼容 PC/2in1：鼠标拖拽平移（PanGesture 响应鼠标左键）、双击缩放、
// 滚轮缩放与触控板双指捏合（轴事件 onAxisEvent）
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Util } from '../../common/Util';
import { ImageCache } from '../../common/ImageCache';
import { SmartImage } from './SmartImage';
import { AppIcon } from './AppIcon';

@Component
export struct CoverViewer {
  @Prop coverUrl: string = '';
  @Prop sourceKey: string = '';
  @Prop isCustom: boolean = false;
  @Prop title: string = '';
  @StorageProp('navBarH') navBarH: number = 0;
  @State zoom: number = 1;
  @State panX: number = 0;
  @State panY: number = 0;
  onClose: () => void = () => {
  };
  onEdit: () => void = () => {
  };
  onDelete: () => void = () => {
  };
  private pinchStartZoom: number = 1;
  private panStartX: number = 0;
  private panStartY: number = 0;
  private axisPinchActive: boolean = false;
  private axisPinchStartZoom: number = 1;

  // ---------------- 缩放与关闭 ----------------

  private closeViewer(): void {
    this.zoom = 1;
    this.panX = 0;
    this.panY = 0;
    this.onClose();
  }

  private resetZoom(): void {
    this.zoom = 1;
    this.panX = 0;
    this.panY = 0;
  }

  // 应用缩放（1x~5x）并同步收拢平移边界；回落到 1x 时复位平移
  private applyZoom(nextZoom: number): void {
    this.zoom = Math.min(5, Math.max(1, nextZoom));
    if (this.zoom <= 1) {
      this.panX = 0;
      this.panY = 0;
      return;
    }
    const limit = 160 * (this.zoom - 1);
    this.panX = Math.min(limit, Math.max(-limit, this.panX));
    this.panY = Math.min(limit, Math.max(-limit, this.panY));
  }

  // PC/2in1 交互（轴事件）：鼠标滚轮缩放、触控板双指捏合缩放
  private handleAxisEvent(event?: AxisEvent): void {
    if (!event) {
      return;
    }
    if (event.hasAxis(AxisType.PINCH_AXIS)) {
      if (!this.axisPinchActive) {
        this.axisPinchActive = true;
        this.axisPinchStartZoom = this.zoom;
      }
      const ratio = event.getPinchAxisScaleValue();
      if (ratio > 0) {
        this.applyZoom(this.axisPinchStartZoom * ratio);
      }
      if (event.action === AxisAction.END || event.action === AxisAction.CANCEL) {
        this.axisPinchActive = false;
      }
      return;
    }
    const delta = event.getVerticalAxisValue();
    if (delta !== 0) {
      this.applyZoom(this.zoom * Math.exp(-delta * 0.005));
    }
  }

  // ---------------- 文件路径辅助 ----------------

  // 保证拿到应用沙箱内可读的裸路径（file:// 去前缀；远程地址经 ImageCache 下载落盘）
  private async ensureLocalPath(context: common.UIAbilityContext): Promise<string> {
    const url = this.coverUrl;
    if (url.indexOf('file://') === 0) {
      return url.substring('file://'.length);
    }
    return await ImageCache.ensureLocal(context, url, this.sourceKey);
  }

  private fileExtOf(path: string): string {
    const q = path.indexOf('?');
    const p = q >= 0 ? path.substring(0, q) : path;
    const dot = p.lastIndexOf('.');
    if (dot >= 0 && p.length - dot <= 6) {
      return p.substring(dot + 1).toLowerCase();
    }
    return 'jpg';
  }

  private safeTitle(): string {
    let t = this.title.trim();
    if (t === '') {
      t = 'cover';
    }
    let out = '';
    for (let i = 0; i < t.length; i++) {
      const ch = t.charAt(i);
      if ('\\/:*?"<>|'.indexOf(ch) >= 0) {
        out += '_';
      } else {
        out += ch;
      }
    }
    return out;
  }

  // ---------------- 保存 / 分享 ----------------

  // 保存封面到图库（对齐 Mihon Save）：弹窗授权 → 复制沙箱图片到媒体库
  private async saveCover(): Promise<void> {
    const context = Util.hostAbilityContext(this.getUIContext());
    const localPath = await this.ensureLocalPath(context);
    if (localPath === '') {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_cover_save_gallery_failed'));
      return;
    }
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const configs: photoAccessHelper.PhotoCreationConfig[] = [
        {
          title: this.safeTitle(),
          fileNameExtension: this.fileExtOf(localPath),
          photoType: photoAccessHelper.PhotoType.IMAGE,
          subtype: photoAccessHelper.PhotoSubtype.DEFAULT,
        }
      ];
      const destUris: Array<string> = await helper.showAssetsCreationDialog([localPath], configs);
      if (destUris.length === 0 || destUris[0] === '') {
        return;
      }
      const dest = await fs.open(destUris[0], fs.OpenMode.WRITE_ONLY);
      const src = await fs.open(localPath, fs.OpenMode.READ_ONLY);
      try {
        await fs.copyFile(src.fd, dest.fd);
      } finally {
        fs.closeSync(src);
        fs.closeSync(dest);
      }
      Util.toastRes(this.getUIContext(), $r('app.string.detail_cover_saved'));
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_cover_save_gallery_failed'));
    }
  }

  // 分享封面（对齐 Mihon Share）：拉起系统分享面板分享图片
  private async shareCover(): Promise<void> {
    const context = Util.hostAbilityContext(this.getUIContext());
    const localPath = await this.ensureLocalPath(context);
    if (localPath === '') {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_cover_share_failed'));
      return;
    }
    try {
      const utdTypeId = utd.getUniformDataTypeByFilenameExtension('.' + this.fileExtOf(localPath),
        utd.UniformDataType.IMAGE);
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: utdTypeId,
        uri: fileUri.getUriFromPath(localPath),
        title: this.title,
      });
      const controller = new systemShare.ShareController(data);
      controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL,
      }).catch((error: BusinessError) => {
        Util.toastRes(this.getUIContext(), $r('app.string.detail_cover_share_failed'));
      });
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_cover_share_failed'));
    }
  }

  // ---------------- 操作栏 ----------------

  @Builder
  actionIcon(iconName: string, onTap: () => void) {
    Stack() {
      AppIcon({ name: iconName, iconSize: 22, tint: '#FFFFFF' })
    }
    .width(40)
    .height(40)
    .borderRadius(20)
    .onClick(() => {
      onTap();
    })
  }

  // 自定义封面已启用时：编辑按钮弹出 编辑/恢复原封面 菜单（对齐 Mihon Edit 下拉）
  @Builder
  editMenuBuilder() {
    Menu() {
      MenuItem({ content: $r('app.string.detail_edit_cover') })
        .onClick(() => {
          this.onEdit();
        })
      MenuItem({ content: $r('app.string.detail_reset_cover') })
        .onClick(() => {
          this.onDelete();
        })
    }
  }

  @Builder
  bottomBarBuilder() {
    Row() {
      // 左侧：关闭
      Row() {
        Stack() {
          AppIcon({ name: 'close', iconSize: 22, tint: '#FFFFFF' })
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .onClick(() => {
          this.closeViewer();
        })
      }
      .padding(4)
      .borderRadius(24)
      .backgroundColor('#99000000')

      // 右侧：分享 / 保存 / 编辑封面
      Row({ space: 2 }) {
        this.actionIcon('share', () => {
          this.shareCover();
        })
        this.actionIcon('download', () => {
          this.saveCover();
        })
        if (this.isCustom) {
          Stack() {
            AppIcon({ name: 'edit', iconSize: 22, tint: '#FFFFFF' })
          }
          .width(40)
          .height(40)
          .borderRadius(20)
          .bindMenu(this.editMenuBuilder)
        } else {
          Stack() {
            AppIcon({ name: 'edit', iconSize: 22, tint: '#FFFFFF' })
          }
          .width(40)
          .height(40)
          .borderRadius(20)
          .onClick(() => {
            this.onEdit();
          })
        }
      }
      .padding(4)
      .borderRadius(24)
      .backgroundColor('#99000000')
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: this.navBarH + 16 })
    .justifyContent(FlexAlign.SpaceBetween)
  }

  build() {
    Column() {
      // 图片区域：Contain 展示，双击/捏合缩放，拖拽平移，单击关闭
      Stack() {
        SmartImage({ url: this.coverUrl, sourceKey: this.sourceKey, fit: ImageFit.Contain, fill: true })
          .scale({ x: this.zoom, y: this.zoom })
          .translate({ x: this.panX, y: this.panY })
      }
      .width('100%')
      .layoutWeight(1)
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          TapGesture({ count: 2 })
            .onAction(() => {
              if (this.zoom > 1) {
                this.resetZoom();
              } else {
                this.applyZoom(2.5);
              }
            }),
          TapGesture({ count: 1 })
            .onAction(() => {
              this.closeViewer();
            })
        )
      )
      .gesture(
        PinchGesture()
          .onActionStart(() => {
            this.pinchStartZoom = this.zoom;
          })
          .onActionUpdate((event: GestureEvent) => {
            this.applyZoom(this.pinchStartZoom * event.scale);
          })
          .onActionEnd(() => {
            if (this.zoom < 1.05) {
              this.resetZoom();
            }
          })
      )
      .gesture(
        PanGesture({ fingers: 1 })
          .onActionStart(() => {
            this.panStartX = this.panX;
            this.panStartY = this.panY;
          })
          .onActionUpdate((event: GestureEvent) => {
            if (this.zoom <= 1) {
              return;
            }
            const limit = 160 * (this.zoom - 1);
            this.panX = Math.min(limit, Math.max(-limit, this.panStartX + event.offsetX));
            this.panY = Math.min(limit, Math.max(-limit, this.panStartY + event.offsetY));
          })
          .onActionEnd(() => {
            if (this.zoom <= 1) {
              this.panX = 0;
              this.panY = 0;
            }
          })
      )
      // PC/2in1：滚轮/触控板捏合缩放
      .onAxisEvent((event?: AxisEvent) => {
        this.handleAxisEvent(event);
      })

      this.bottomBarBuilder()
    }
    .width('100%')
    .height('100%')
  }
}
