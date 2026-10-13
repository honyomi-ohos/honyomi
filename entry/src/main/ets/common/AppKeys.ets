// AppStorage 键集中登记（全工程唯一清单）
// 说明：@StorageLink/@StorageProp 装饰器参数只接受字符串字面量，
// 因此装饰器调用点直接写字面量；EntryAbility/服务层等非装饰器
// 调用点应引用本类常量，禁止新增裸字符串键。
export class AppKeys {
  // 主题外观
  static readonly IS_DARK: string = 'isDark';
  static readonly IS_DARK_SYSTEM: string = 'isDarkSystem';
  static readonly PALETTE: string = 'palette';
  static readonly ACCENT: string = 'accent';
  static readonly AMOLED: string = 'amoled';
  static readonly APP_LANGUAGE: string = 'appLanguage';
  // 系统避让区
  static readonly STATUS_BAR_H: string = 'statusBarH';
  static readonly NAV_BAR_H: string = 'navBarH';
  // 数据脏标记（计数器递增触发 @Watch 刷新）
  static readonly LIB_DIRTY: string = 'libDirty';
  static readonly PLUGINS_DIRTY: string = 'pluginsDirty';
  static readonly EXT_REPO_REFRESH: string = 'extRepoRefresh';
  static readonly EXT_LOCAL_INSTALL: string = 'extLocalInstall';
  // 页签重复点击信号（计数器递增）
  static readonly LIB_RESELECT: string = 'libReselect';
  static readonly HISTORY_RESELECT: string = 'historyReselect';
  // 全局功能开关
  static readonly DOWNLOADED_ONLY: string = 'downloadedOnly';
  static readonly INCOGNITO: string = 'incognito';
  // 跨页通信
  static readonly CARD_ACTION: string = 'cardAction';
  static readonly CF_CHALLENGE_URL: string = 'cfChallengeUrl';
  static readonly LIB_SELECTION_COUNT: string = 'libSelectionCount';
}
