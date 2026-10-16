// AppStorage 键集中登记（全工程唯一清单）
// 说明：@StorageLink/@StorageProp 装饰器参数只接受字符串字面量，
// 因此装饰器调用点直接写字面量；EntryAbility/服务层等非装饰器
// 调用点应引用本类常量，禁止新增裸字符串键。
export class AppKeys {
  // 主题外观
  static readonly IS_DARK: string = 'isDark';
  static readonly IS_DARK_SYSTEM: string = 'isDarkSystem';
  static readonly PALETTE: string = 'palette';
  static readonly APP_THEME: string = 'appTheme';
  static readonly AMOLED: string = 'amoled';
  static readonly APP_LANGUAGE: string = 'appLanguage';
  // 系统避让区
  static readonly STATUS_BAR_H: string = 'statusBarH';
  static readonly NAV_BAR_H: string = 'navBarH';
  // 窗口宽度（px，Index 随窗口尺寸变化写入，页面经 @StorageProp 读取做宽窄适配）
  static readonly WINDOW_W: string = 'windowW';
  // 数据脏标记（计数器递增触发 @Watch 刷新）
  static readonly LIB_DIRTY: string = 'libDirty';
  static readonly PLUGINS_DIRTY: string = 'pluginsDirty';
  static readonly EXT_REPO_REFRESH: string = 'extRepoRefresh';
  static readonly EXT_LOCAL_INSTALL: string = 'extLocalInstall';
  // 页签重复点击信号（计数器递增）
  static readonly LIB_RESELECT: string = 'libReselect';
  static readonly HISTORY_RESELECT: string = 'historyReselect';
  // 详情页回退书架/主页的搜索请求（计数触发，查询词经 libSearchQuery 传递）
  static readonly LIB_SEARCH_REQ: string = 'libSearchReq';
  static readonly LIB_SEARCH_QUERY: string = 'libSearchQuery';
  // 全局功能开关
  static readonly DOWNLOADED_ONLY: string = 'downloadedOnly';
  static readonly INCOGNITO: string = 'incognito';
  static readonly SHOW_NSFW: string = 'showNsfw';
  // 跨页通信
  static readonly CARD_ACTION: string = 'cardAction';
  // 视频播放器外部快进/跳转指令（JSON 字符串，VideoPlayerPage 消费）
  static readonly VIDEO_SEEK: string = 'videoSeek';
  static readonly CF_CHALLENGE_URL: string = 'cfChallengeUrl';
  // CF 质询通过信号（计数器递增代表验证完成，JsvmSource 轮询读取）
  static readonly CF_VERIFIED_TICK: string = 'cfVerifiedTick';
  static readonly LIB_SELECTION_COUNT: string = 'libSelectionCount';
  // 更新抓取失败章节数（UpdatesPage 徽标）
  static readonly UPDATE_FAILED_COUNT: string = 'updateFailedCount';
  // 备份结果标记（设置页展示上次备份是否失败）
  static readonly LAST_BACKUP_FAILED: string = 'lastBackupFailed';
  // 主页底部页签区高度（px，Index 窗口测量写入）
  static readonly TAB_PAD_H: string = 'tabPadH';
  // 应用锁锁定态（EntryAbility 判定写入，LockOverlay 消费）
  static readonly APP_LOCKED: string = 'appLocked';
}
