// 封面查看器（对齐 Mihon MangaCoverDialog）：
// 点击封面进入全屏查看，底部左侧关闭、右侧分享/保存/编辑封面；
// 缩放/平移实现参考 PicturePreview：读取图片原始宽高按容器适配，
// matrix4 矩阵缩放 + translate 平移 + 真实边界约束，
// 捏合缩放以捏合中心为锚点，双击动画缩放/复位；
// 兼容 PC/2in1：鼠标拖拽平移（PanGesture 响应鼠标左键）、
// 滚轮缩放与触控板双指捏合（轴事件 onAxisEvent）
import { common } from '@kit.AbilityKit';
import { matrix4 } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Util } from '../../common/Util';
import { ImageCache } from '../../common/ImageCache';
import { AppIcon } from './AppIcon';
import { CoverPlaceholder } from './CoverPlaceholder';

// 最大缩放倍数（对齐 PicturePreview calcFitScaleRatio 的上限思路，封面场景固定 5x）
const MAX_ZOOM: number = 5;

@Component
export struct CoverViewer {
  @Prop coverUrl: string = '';
  @Prop sourceKey: string = '';
  @Prop isCustom: boolean = false;
  @Prop title: string = '';
  // 是否展示“编辑封面”入口（条目详情等只读场景传 false，仅查看/保存/分享）
  @Prop allowEdit: boolean = true;
  // 全模态铺满整个窗口矩形（含状态栏区域）：图片区需按 statusBarH 下移避开状态栏
  @StorageProp('statusBarH') statusBarH: number = 0;
  // 图片展示：先解析本地路径并读取原始宽高，再按容器适配出实际显示宽高
  // localPath 为裸沙箱路径（save/share 用），displayPath 为渲染地址：
  // Image 组件不能直接传入应用沙箱路径，须转为 file:// 沙箱 URI（faqs-arkui-154）
  @State localPath: string = '';
  @State displayPath: string = '';
  @State loadFailed: boolean = false;
  @State imageWidth: number = 0;
  @State imageHeight: number = 0;
  // 缩放/平移状态（参考 PicturePreview ImageModel）
  @State matrix: matrix4.Matrix4Transit = matrix4.identity().copy();
  @State curScale: number = 1;
  @State curOffsetX: number = 0;
  @State curOffsetY: number = 0;
  // 已放大时收紧平移触发距离，未放大时放宽，避免抢占捏合/双击
  @State panDistance: number = 50;
  private lastScale: number = 1;
  private lastOffsetX: number = 0;
  private lastOffsetY: number = 0;
  private maxOffsetX: number = 0;
  private minOffsetX: number = 0;
  private maxOffsetY: number = 0;
  private minOffsetY: number = 0;
  private centerX: number = 0.5;
  private centerY: number = 0.5;
  private naturalWidth: number = 0;
  private naturalHeight: number = 0;
  private componentWidth: number = 0;
  private componentHeight: number = 0;
  private axisPinchActive: boolean = false;
  onClose: () => void = () => {
  };
  onEdit: () => void = () => {
  };
  onDelete: () => void = () => {
  };

  aboutToAppear(): void {
    // 无封面（本地资源等）：跳过解析，直接显示默认封面占位
    if (this.coverUrl !== '') {
      this.initImage();
    }
  }

  // ---------------- 图片初始化 ----------------

  @Builder
  loadingPlaceholder() {
    Column() {
      LoadingProgress()
        .width(28)
        .height(28)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  failedPlaceholder() {
    Column() {
      AppIcon({ name: 'error', iconSize: 24 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  // ---------------- 缩放与平移（参考 PicturePreview） ----------------

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
        if (this.allowEdit) {
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
      }
      .padding(4)
      .borderRadius(24)
      .backgroundColor('#99000000')
    }
    .width('100%')
    // 手势指示条贴近屏幕底边（约 10vp），底栏固定 16vp 即可让开；
    // 旧 navBarH+16 会把按钮抬高手势避让区上沿，视觉上形成大段空隙
    .padding({ left: 16, right: 16, bottom: 16 })
    .justifyContent(FlexAlign.SpaceBetween)
  }

  build() {
    Column() {
      // 图片区域：参考 PicturePreview，按容器适配尺寸，矩阵缩放 + 平移 + 边界约束
      Stack() {
        if (this.coverUrl === '') {
          // 无封面：默认封面占位（点击仍可关闭）
          CoverPlaceholder({ iconSize: 56 })
            .width('100%')
            .height('100%')
        } else if (this.displayPath !== '' && !this.loadFailed) {
          Image(this.displayPath)
            .width(this.imageWidth)
            .height(this.imageHeight)
            .objectFit(ImageFit.Contain)
            .transform(this.matrix)
            .translate({ x: this.curOffsetX, y: this.curOffsetY })
            .onError(() => {
              this.loadFailed = true;
            })
        } else if (this.loadFailed) {
          this.failedPlaceholder()
        } else {
          this.loadingPlaceholder()
        }
      }
      .width('100%')
      .layoutWeight(1)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const w = newValue.width;
        const h = newValue.height;
        if (typeof w === 'number' && typeof h === 'number') {
          this.componentWidth = w;
          this.componentHeight = h;
          this.fitImage();
        }
      })
      .parallelGesture(
        GestureGroup(GestureMode.Exclusive,
          // 单指平移（含鼠标拖拽）：参考 PicturePreview pan_gesture
          PanGesture({ fingers: 1, distance: this.panDistance })
            .onActionUpdate((event: GestureEvent) => {
              this.onScale(1, event.offsetX, event.offsetY);
              this.pictureBoundaryRestriction();
            })
            .onActionEnd(() => {
              this.gestureEnd();
            }),
          // 双指捏合缩放：以捏合中点为锚点（参考 PicturePreview pinch）
          PinchGesture({ fingers: 2, distance: 1 })
            .onActionStart((event: GestureEvent) => {
              this.pinchStart(event);
            })
            .onActionUpdate((event: GestureEvent) => {
              this.onScale(event.scale, event.offsetX, event.offsetY);
              this.pictureScaling(this.curScale);
              this.pictureBoundaryRestriction();
            })
            .onActionEnd(() => {
              this.pinchEnd();
            }),
          // 双击动画缩放/复位
          TapGesture({ count: 2 })
            .onAction(() => {
              this.doubleTap();
            }),
          // 单击关闭
          TapGesture({ count: 1 })
            .onAction(() => {
              this.closeViewer();
            })
        ), GestureMask.Normal)
      // PC/2in1：滚轮/触控板捏合缩放
      .onAxisEvent((event?: AxisEvent) => {
        this.handleAxisEvent(event);
      })

      this.bottomBarBuilder()
    }
    .width('100%')
    .height('100%')
    // 全模态从 y=0 起绘会压住状态栏：顶部按 statusBarH 避让，图片区整体下移
    .padding({ top: this.statusBarH })
  }

  // 解析本地路径并读取原始宽高（参考 PicturePreview initCurrentImageInfo）
  private async initImage(): Promise<void> {
    const context = Util.hostAbilityContext(this.getUIContext());
    try {
      const path = await this.ensureLocalPath(context);
      if (path === '') {
        // 下载落盘失败：回退原始地址直连显示（与旧 SmartImage 行为一致）
        this.localPath = '';
        this.displayPath = this.coverUrl;
        this.fitImage();
        return;
      }
      this.localPath = path;
      this.displayPath = path.indexOf('/') === 0 ? `file://${path}` : path;
      // ImageSource 解码完成后必须 release（失败路径经 finally 同样释放）
      let source: image.ImageSource | undefined = undefined;
      try {
        source = image.createImageSource(path);
        const info = await source.getImageInfo();
        this.naturalWidth = info.size.width;
        this.naturalHeight = info.size.height;
      } catch (e) {
        // 读取宽高失败：退化为容器尺寸 + Contain 展示
        this.naturalWidth = 0;
        this.naturalHeight = 0;
      } finally {
        if (source !== undefined) {
          source.release().catch((_e: BusinessError): void => {
          });
        }
      }
      this.fitImage();
    } catch (e) {
      this.loadFailed = true;
    }
  }

  // 按容器与图片原始宽高计算适配后的显示尺寸（完整可见）
  private fitImage(): void {
    if (this.componentWidth <= 0 || this.componentHeight <= 0) {
      return;
    }
    if (this.naturalWidth <= 0 || this.naturalHeight <= 0) {
      this.imageWidth = this.componentWidth;
      this.imageHeight = this.componentHeight;
      return;
    }
    const ratio = Math.min(this.componentWidth / this.naturalWidth, this.componentHeight / this.naturalHeight);
    this.imageWidth = this.naturalWidth * ratio;
    this.imageHeight = this.naturalHeight * ratio;
  }

  private closeViewer(): void {
    this.onClose();
  }

  // 通用矩阵缩放（参考 PicturePreview pictureScaling）
  private pictureScaling(scale: number): void {
    this.matrix = matrix4.identity().scale({ x: scale, y: scale }).copy();
  }

  // 偏移复位（参考 PicturePreview offsetReset）
  private offsetReset(): void {
    this.curOffsetX = 0;
    this.curOffsetY = 0;
    this.lastOffsetX = 0;
    this.lastOffsetY = 0;
  }

  // 手势结束：固化当前缩放/偏移（参考 PicturePreview gestureEnd）
  private gestureEnd(): void {
    this.lastScale = this.curScale;
    this.lastOffsetX = this.curOffsetX;
    this.lastOffsetY = this.curOffsetY;
    this.panDistance = this.curScale > 1.01 ? 3 : 50;
  }

  // 计算图片可平移的边界范围（参考 PicturePreview evaluateOffsetRange）
  private evaluateOffsetRange(): void {
    const scaledWidth = this.imageWidth * this.curScale;
    const scaledHeight = this.imageHeight * this.curScale;
    if (scaledWidth > this.componentWidth) {
      const limit = (scaledWidth - this.componentWidth) / 2;
      this.maxOffsetX = limit;
      this.minOffsetX = -limit;
    } else {
      this.maxOffsetX = 0;
      this.minOffsetX = 0;
    }
    if (scaledHeight > this.componentHeight) {
      const limit = (scaledHeight - this.componentHeight) / 2;
      this.maxOffsetY = limit;
      this.minOffsetY = -limit;
    } else {
      this.maxOffsetY = 0;
      this.minOffsetY = 0;
    }
  }

  // 平移越界约束：超界夹回边界，图片小于容器时强制居中（参考 PicturePreview pictureBoundaryRestriction）
  private pictureBoundaryRestriction(): void {
    if (this.curOffsetX > this.maxOffsetX) {
      this.curOffsetX = this.maxOffsetX;
    } else if (this.curOffsetX < this.minOffsetX) {
      this.curOffsetX = this.minOffsetX;
    }
    if (this.curOffsetY > this.maxOffsetY) {
      this.curOffsetY = this.maxOffsetY;
    } else if (this.curOffsetY < this.minOffsetY) {
      this.curOffsetY = this.minOffsetY;
    }
    const scaledWidth = this.imageWidth * this.curScale;
    const scaledHeight = this.imageHeight * this.curScale;
    if (scaledWidth <= this.componentWidth) {
      this.curOffsetX = 0;
    }
    if (scaledHeight <= this.componentHeight) {
      this.curOffsetY = 0;
    }
  }

  // ---------------- 文件路径辅助 ----------------

  // 计算缩放锚点相对图片的百分比位置（入参为容器内局部坐标，参考 PicturePreview evaluateCenter）
  private evaluateCenter(posX: number, posY: number): void {
    const displayWidth = this.imageWidth * this.lastScale;
    const displayHeight = this.imageHeight * this.lastScale;
    const imgX = (this.componentWidth - displayWidth) / 2 + this.lastOffsetX;
    const imgY = (this.componentHeight - displayHeight) / 2 + this.lastOffsetY;
    const cX = Math.max((posX - imgX) / displayWidth, 0);
    const cY = Math.max((posY - imgY) / displayHeight, 0);
    this.centerX = 1 - cX;
    this.centerY = 1 - cY;
  }

  // 计算当前偏移与缩放（参考 PicturePreview onScale）：锚点补偿 + 上下限夹取
  private onScale(scale: number, offX: number, offY: number): void {
    const next = this.lastScale * scale;
    if (next > MAX_ZOOM) {
      this.curScale = MAX_ZOOM;
    } else if (next < 1) {
      this.curScale = 1;
    } else {
      this.curScale = next;
    }
    // 恰好到达上限时略微回退，保证上限附近偏移仍可更新（参考 PicturePreview）
    if (next >= MAX_ZOOM) {
      this.curScale = MAX_ZOOM - 0.001;
    }
    this.evaluateOffsetRange();
    this.curOffsetY =
      (this.lastOffsetY + offY) + (0.5 - this.centerY) * this.imageHeight * (1 - scale) * this.lastScale;
    this.curOffsetX = (this.lastOffsetX + offX) + (0.5 - this.centerX) * this.imageWidth * (1 - scale) * this.lastScale;
  }

  // 捏合开始：以双指中点为缩放锚点（参考 PicturePreview pinchGestureStart）
  private pinchStart(event: GestureEvent): void {
    const fingers = event.fingerList;
    if (fingers.length < 2) {
      this.centerX = 0.5;
      this.centerY = 0.5;
      return;
    }
    const midX = ((fingers[0].localX ?? 0) + (fingers[1].localX ?? 0)) / 2;
    const midY = ((fingers[0].localY ?? 0) + (fingers[1].localY ?? 0)) / 2;
    this.evaluateCenter(midX, midY);
  }

  // ---------------- 保存 / 分享 ----------------

  // 捏合结束：低于 1x 动画复位，达到上限略回弹（参考 PicturePreview pinchGestureEnd）
  private pinchEnd(): void {
    this.getUIContext().animateTo({ duration: 300, curve: Curve.Smooth }, () => {
      if (this.curScale <= 1) {
        this.curScale = 1;
        this.pictureScaling(1);
        this.offsetReset();
      } else if (this.curScale >= MAX_ZOOM) {
        this.curScale = MAX_ZOOM - 0.1;
        this.pictureScaling(this.curScale);
        this.evaluateOffsetRange();
      }
      this.gestureEnd();
    });
  }

  // 双击：已放大则动画复位，否则动画放大到上限（参考 PicturePreview doubleTapGesture）
  private doubleTap(): void {
    const reset = this.lastScale > 1;
    this.getUIContext().animateTo({ duration: 300, curve: Curve.Smooth }, () => {
      if (reset) {
        this.curScale = 1;
        this.pictureScaling(1);
        this.offsetReset();
      } else {
        this.curScale = MAX_ZOOM - 0.001;
        this.pictureScaling(this.curScale);
        this.offsetReset();
      }
      this.evaluateOffsetRange();
      this.gestureEnd();
    });
  }

  // ---------------- 占位 ----------------

  // PC/2in1 交互（轴事件）：鼠标滚轮缩放、触控板双指捏合缩放（居中锚点）
  private handleAxisEvent(event?: AxisEvent): void {
    if (!event) {
      return;
    }
    if (event.hasAxis(AxisType.PINCH_AXIS)) {
      if (!this.axisPinchActive) {
        this.axisPinchActive = true;
        this.gestureEnd();
        this.centerX = 0.5;
        this.centerY = 0.5;
      }
      const ratio = event.getPinchAxisScaleValue();
      if (ratio > 0) {
        this.onScale(ratio, 0, 0);
        this.pictureScaling(this.curScale);
        this.pictureBoundaryRestriction();
      }
      if (event.action === AxisAction.END || event.action === AxisAction.CANCEL) {
        this.axisPinchActive = false;
        this.gestureEnd();
      }
      return;
    }
    const delta = event.getVerticalAxisValue();
    if (delta !== 0) {
      this.gestureEnd();
      this.centerX = 0.5;
      this.centerY = 0.5;
      this.onScale(Math.exp(-delta * 0.005), 0, 0);
      this.pictureScaling(this.curScale);
      this.pictureBoundaryRestriction();
      this.gestureEnd();
    }
  }

  // 保证拿到应用沙箱内可读的裸路径（file:// 去前缀；远程地址经 ImageCache 下载落盘）
  private async ensureLocalPath(context: common.UIAbilityContext): Promise<string> {
    const url = this.coverUrl;
    if (url.indexOf('file://') === 0) {
      return url.substring('file://'.length);
    }
    return await ImageCache.ensureLocal(context, url, this.sourceKey);
  }

  // ---------------- 操作栏 ----------------

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

  // 保存封面到图库（对齐 Mihon Save）：弹窗授权 → 复制沙箱图片到媒体库
  private async saveCover(): Promise<void> {
    const context = Util.hostAbilityContext(this.getUIContext());
    try {
      const localPath = await this.ensureLocalPath(context);
      if (localPath === '') {
        Util.toastRes(this.getUIContext(), $r('app.string.detail_cover_save_gallery_failed'));
        return;
      }
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
      let dest: fs.File | undefined = undefined;
      let src: fs.File | undefined = undefined;
      try {
        dest = await fs.open(destUris[0], fs.OpenMode.WRITE_ONLY);
        src = await fs.open(localPath, fs.OpenMode.READ_ONLY);
        await fs.copyFile(src.fd, dest.fd);
      } finally {
        if (src !== undefined) {
          fs.closeSync(src);
        }
        if (dest !== undefined) {
          fs.closeSync(dest);
        }
      }
      Util.toastRes(this.getUIContext(), $r('app.string.detail_cover_saved'));
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_cover_save_gallery_failed'));
    }
  }

  // 分享封面（对齐 Mihon Share）：拉起系统分享面板分享图片
  private async shareCover(): Promise<void> {
    const context = Util.hostAbilityContext(this.getUIContext());
    try {
      const localPath = await this.ensureLocalPath(context);
      if (localPath === '') {
        Util.toastRes(this.getUIContext(), $r('app.string.detail_cover_share_failed'));
        return;
      }
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
}
