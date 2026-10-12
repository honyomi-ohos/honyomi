// 本地源文件夹管理（Mihon local source 风格）：固定一个用户文件夹作为本地源。
// 系统不允许普通应用直接遍历用户目录（fs.listFileSync 仅接受沙箱路径），
// 因此“扫描本地”= 把持久化授权后的文件夹整树 fs.copy 同步进沙箱 local_root，
// 三个本地源（漫画/小说/视频）再从 local_root 下各自的预置子文件夹扫描归类。
// 指定文件夹后会自动创建 comic/novel/anime 三个预置子文件夹（尽力而为）。
// 授权通过 fileShare.persistPermission 持久化（ohos.permission.FILE_ACCESS_PERSIST，
// normal 级系统授权），应用/设备重启后经 activatePermission 重新激活。
import { fileIo as fs, fileUri, picker, fileShare } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Settings } from '../common/Settings';

const TAG = 'LocalFolderManager';

export class LocalFolderManager {
  // 预置子文件夹：每个本地源只扫描自己对应的子文件夹
  static readonly COMIC_SUBDIR = 'comic';
  static readonly NOVEL_SUBDIR = 'novel';
  static readonly ANIME_SUBDIR = 'anime';

  static localSubDirs(): string[] {
    return [LocalFolderManager.COMIC_SUBDIR, LocalFolderManager.NOVEL_SUBDIR, LocalFolderManager.ANIME_SUBDIR];
  }

  // 同步目标：沙箱 filesDir/local_root（三个本地源共用）
  static syncedRootPath(filesDir: string): string {
    return `${filesDir}/local_root`;
  }

  static hasFolder(): boolean {
    return Settings.getLocalFolderUri() !== '';
  }

  static folderName(): string {
    const name = Settings.getLocalFolderName();
    return name !== '' ? name : 'local';
  }

  // 从 picker 返回的 URI 提取最后一段作为名称（文件夹名/文件名）
  static uriName(uri: string): string {
    const segs = uri.split('/');
    const raw = segs.length > 0 ? segs[segs.length - 1] : '';
    let name = '';
    try {
      name = decodeURIComponent(raw);
    } catch (e) {
      name = raw;
    }
    if (name.trim() === '') {
      name = `local_${Date.now()}`;
    }
    return name;
  }

  // 选择文件夹并持久化授权；返回 false 表示用户取消。
  // 失败时抛出 message 为 'PICK'（选择器失败）或 'PERSIST'（授权持久化失败）的 Error。
  static async chooseFolder(context: common.UIAbilityContext): Promise<boolean> {
    const options = new picker.DocumentSelectOptions();
    options.selectMode = picker.DocumentSelectMode.FOLDER;
    options.maxSelectNumber = 1;
    // 必须传入 UIAbilityContext 构造：无参构造为不推荐用法，概率性拉起异常
    const docPicker = new picker.DocumentViewPicker(context);
    let uris: Array<string> = [];
    try {
      uris = await docPicker.select(options);
    } catch (e) {
      throw new Error('PICK');
    }
    if (uris.length === 0) {
      return false;
    }
    const uri = uris[0];
    try {
      const policy: fileShare.PolicyInfo = {
        uri: uri,
        operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE,
      };
      await fileShare.persistPermission([policy]);
    } catch (e) {
      throw new Error('PERSIST');
    }
    // 释放旧文件夹的持久化授权（尽力而为，失败不影响新选择）
    const oldUri = Settings.getLocalFolderUri();
    if (oldUri !== '' && oldUri !== uri) {
      const modes: fileShare.OperationMode[] = [
        fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE,
        fileShare.OperationMode.READ_MODE,
      ];
      for (const mode of modes) {
        try {
          const oldPolicy: fileShare.PolicyInfo = {
            uri: oldUri,
            operationMode: mode,
          };
          await fileShare.revokePermission([oldPolicy]);
          break;
        } catch (e) {
          // 换下一种模式重试
        }
      }
    }
    Settings.setLocalFolderUri(uri);
    Settings.setLocalFolderName(LocalFolderManager.uriName(uri));
    // 选定后立即创建预置子文件夹（此时 Picker 临时读写授权仍在，创建成功率最高）
    await LocalFolderManager.ensureSubDirs(context, uri);
    return true;
  }

  // 同步本地源文件夹：激活授权 → 补建预置子文件夹 → 整树拷贝到中转目录 → 原子替换 local_root。
  // 失败时抛出 message 为 'ACCESS'（授权失效，需重新选择）或其他错误的 Error。
  static async sync(context: common.UIAbilityContext): Promise<void> {
    const uri = Settings.getLocalFolderUri();
    if (uri === '') {
      throw new Error('ACCESS');
    }
    // 应用/设备重启后持久化授权需要先激活；优先读写（维护预置子文件夹），旧版仅读授权回退只读激活
    try {
      const policy: fileShare.PolicyInfo = {
        uri: uri,
        operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE,
      };
      await fileShare.activatePermission([policy]);
    } catch (e) {
      try {
        const readPolicy: fileShare.PolicyInfo = {
          uri: uri,
          operationMode: fileShare.OperationMode.READ_MODE,
        };
        await fileShare.activatePermission([readPolicy]);
      } catch (e2) {
        throw new Error('ACCESS');
      }
    }
    // 同步前补建预置子文件夹（尽力而为，失败不影响同步）
    await LocalFolderManager.ensureSubDirs(context, uri);
    const filesDir = context.filesDir;
    const rootPath = LocalFolderManager.syncedRootPath(filesDir);
    const staging = `${filesDir}/.local_root_staging`;
    LocalFolderManager.removeQuietly(staging);
    try {
      fs.mkdirSync(staging, true);
      await fs.copy(uri, fileUri.getUriFromPath(staging));
      // fs.copy 目录语义兼容：源目录可能整体落在中转目录之下
      const nested = `${staging}/${LocalFolderManager.uriName(uri)}`;
      const contentRoot = fs.accessSync(nested) ? nested : staging;
      LocalFolderManager.removeQuietly(rootPath);
      fs.renameSync(contentRoot, rootPath);
      Settings.setLastLocalSyncAt(Date.now());
    } catch (e) {
      LocalFolderManager.removeQuietly(staging);
      throw e as Error;
    }
    LocalFolderManager.removeQuietly(staging);
  }

  // 在用户文件夹内创建预置子文件夹（尽力而为）：文件夹只读或接口不支持时静默跳过，
  // 各本地源扫描时按空目录处理，空态会提示对应的子文件夹名。
  static async ensureSubDirs(context: common.UIAbilityContext, folderUri: string): Promise<void> {
    for (const name of LocalFolderManager.localSubDirs()) {
      await LocalFolderManager.ensureSubDir(context, folderUri, name);
    }
  }

  private static async ensureSubDir(context: common.UIAbilityContext, folderUri: string, name: string): Promise<void> {
    const destUri = `${folderUri}/${name}`;
    // 已存在（statSync 支持用户目录 URI）：直接跳过
    try {
      fs.statSync(destUri);
      return;
    } catch (e) {
      // 不存在时继续尝试创建
    }
    // 沙箱内准备与子文件夹同名的空目录模板（目录拷贝落在目标下时以模板名命名）
    const template = `${context.filesDir}/.local_subdirs/${name}`;
    try {
      if (!fs.accessSync(template)) {
        fs.mkdirSync(template, true);
      }
    } catch (e) {
      const prepErr = e as BusinessError;
      hilog.warn(0x0000, TAG, 'prepare template %{public}s: %{public}d %{public}s',
        [name, prepErr.code, prepErr.message]);
      return;
    }
    // 方式一：mkdir（部分版本支持 URI）
    try {
      fs.mkdirSync(destUri);
      hilog.info(0x0000, TAG, 'subdir %{public}s created via mkdir', [name]);
      return;
    } catch (e) {
      const mkdirErr = e as BusinessError;
      hilog.warn(0x0000, TAG, 'mkdir %{public}s: %{public}d %{public}s',
        [name, mkdirErr.code, mkdirErr.message]);
    }
    // 方式二：向“不存在”的目标 URI 拷贝模板，目标即成为该目录的副本
    try {
      await fs.copy(fileUri.getUriFromPath(template), destUri);
      hilog.info(0x0000, TAG, 'subdir %{public}s created via copy', [name]);
      return;
    } catch (e) {
      const copyErr = e as BusinessError;
      hilog.warn(0x0000, TAG, 'copy %{public}s: %{public}d %{public}s',
        [name, copyErr.code, copyErr.message]);
    }
    // 方式三：向已存在的用户文件夹拷贝模板。目录拷贝语义与同步一致：
    // 源目录会落在目标目录之下，即创建 <文件夹>/<name>。
    try {
      await fs.copy(fileUri.getUriFromPath(template), folderUri);
      try {
        fs.statSync(destUri);
        hilog.info(0x0000, TAG, 'subdir %{public}s created via copy-into', [name]);
      } catch (e) {
        hilog.warn(0x0000, TAG, 'copy-into %{public}s landed unexpectedly', [name]);
      }
    } catch (e) {
      const intoErr = e as BusinessError;
      hilog.warn(0x0000, TAG, 'copy-into %{public}s: %{public}d %{public}s',
        [name, intoErr.code, intoErr.message]);
    }
  }

  // 目录内（递归）是否存在符合后缀的文件（提前返回，用于作品目录内容归类）
  static hasFileWithExts(dir: string, exts: string[]): boolean {
    if (!fs.accessSync(dir)) {
      return false;
    }
    const entries = fs.listFileSync(dir);
    for (const entry of entries) {
      if (entry === '.extracted' || entry.startsWith('.staging_')) {
        continue;
      }
      const fullPath = `${dir}/${entry}`;
      if (LocalFolderManager.matchesExt(entry, exts)) {
        return true;
      }
      if (fs.statSync(fullPath).isDirectory() && LocalFolderManager.hasFileWithExts(fullPath, exts)) {
        return true;
      }
    }
    return false;
  }

  static matchesExt(name: string, exts: string[]): boolean {
    const lower = name.toLowerCase();
    for (const ext of exts) {
      if (lower.endsWith(ext)) {
        return true;
      }
    }
    return false;
  }

  private static removeQuietly(path: string): void {
    try {
      if (fs.accessSync(path)) {
        fs.rmdirSync(path);
      }
    } catch (e) {
      // 忽略清理失败
    }
  }
}
