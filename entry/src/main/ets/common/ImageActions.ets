// 图片操作助手：保存到图库 / 系统分享 / 复制到剪贴板
// （从 CoverViewer 的保存/分享逻辑提炼，供阅读器等页面复用；
// 传入的 localPath 须为应用沙箱内裸路径，可由 ImageCache.ensureLocal 获得）
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class ImageActions {
  // 从 URL/路径提取扩展名（去 query，兜底 jpg）
  static fileExtOf(path: string): string {
    const q = path.indexOf('?');
    const p = q >= 0 ? path.substring(0, q) : path;
    const dot = p.lastIndexOf('.');
    if (dot >= 0 && p.length - dot <= 6) {
      return p.substring(dot + 1).toLowerCase();
    }
    return 'jpg';
  }

  // 文件名安全化：替换 Windows/HarmonyOS 非法字符
  static safeName(title: string): string {
    let t = title.trim();
    if (t === '') {
      t = 'image';
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

  // 保存沙箱图片到媒体库：弹窗授权 → 复制文件内容到授权 URI
  // 返回 'ok'（已保存）| 'declined'（用户在系统弹窗中拒绝）| 'error'（系统弹窗不可用等故障）
  static async saveToGallery(context: common.UIAbilityContext, localPath: string,
    title: string): Promise<string> {
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const configs: photoAccessHelper.PhotoCreationConfig[] = [
        {
          title: title,
          fileNameExtension: ImageActions.fileExtOf(localPath),
          photoType: photoAccessHelper.PhotoType.IMAGE,
          subtype: photoAccessHelper.PhotoSubtype.DEFAULT,
        }
      ];
      const srcUri: string = fileUri.getUriFromPath(localPath);
      const destUris: Array<string> = await helper.showAssetsCreationDialog([srcUri], configs);
      hilog.info(0x0001, 'ImageActions', 'save dialog returned %{public}d uris', destUris.length);
      if (destUris.length === 0 || destUris[0] === '') {
        return 'declined';
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
      return 'ok';
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.error(0x0001, 'ImageActions', 'saveToGallery failed: %{public}d %{public}s',
        err.code, err.message);
      return 'error';
    }
  }

  // SaveButton 安全控件授权后直接创建媒体资源并写入
  // （系统保存对话框不可用时的回退路径，须在 SaveButton onClick 授权有效期内调用）
  static async saveViaCreateAsset(context: common.UIAbilityContext, localPath: string,
    title: string): Promise<boolean> {
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const options: photoAccessHelper.CreateOptions = { title: title };
      const uri: string = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE,
        ImageActions.fileExtOf(localPath), options);
      let dest: fs.File | undefined = undefined;
      let src: fs.File | undefined = undefined;
      try {
        dest = await fs.open(uri, fs.OpenMode.READ_WRITE);
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
      return true;
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.error(0x0001, 'ImageActions', 'saveViaCreateAsset failed: %{public}d %{public}s',
        err.code, err.message);
      return false;
    }
  }

  // 拉起系统分享面板分享沙箱图片
  static async share(context: common.UIAbilityContext, localPath: string,
    title: string): Promise<boolean> {
    try {
      const utdTypeId = utd.getUniformDataTypeByFilenameExtension('.' + ImageActions.fileExtOf(localPath),
        utd.UniformDataType.IMAGE);
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: utdTypeId,
        uri: fileUri.getUriFromPath(localPath),
        title: title,
      });
      const controller = new systemShare.ShareController(data);
      await controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL,
      });
      return true;
    } catch (_e) {
      return false;
    }
  }

  // 复制沙箱图片到系统剪贴板（PixelMap 形式，可粘贴到聊天/笔记等应用）
  static async copyToClipboard(localPath: string): Promise<boolean> {
    let source: image.ImageSource | undefined = undefined;
    try {
      source = image.createImageSource(localPath);
      const pixelMap = await source.createPixelMap();
      const data = pasteboard.createData(pasteboard.MIMETYPE_PIXELMAP, pixelMap);
      await pasteboard.getSystemPasteboard().setData(data);
      return true;
    } catch (_e) {
      return false;
    } finally {
      if (source !== undefined) {
        source.release();
      }
    }
  }
}
