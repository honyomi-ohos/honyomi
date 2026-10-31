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
  // 插件加载完成标志（loadAll 结束后置 true）：NSFW 过滤据此区分
  // 「插件尚未加载完」（源未注册保持隐藏防闪现）与「插件未安装」（如备份恢复后待装，保留显示）
  static readonly PLUGINS_LOADED: string = 'pluginsLoaded';
  static readonly EXT_REPO_REFRESH: string = 'extRepoRefresh';
  static readonly EXT_LOCAL_INSTALL: string = 'extLocalInstall';
  // 扩展可更新数量（checkExtensionUpdates 发布，徽标/设置页副标题消费）
  static readonly EXT_UPDATE_COUNT: string = 'extUpdateCount';
  // 仓库索引缓存更新信号（计数器递增；PluginService 刷新索引/图标预热完成后发布，
  // 浏览-插件面板 @Watch 重读缓存刷新列表）
  static readonly EXT_REPO_CACHE_TICK: string = 'extRepoCacheTick';
  // 页签重复点击信号（计数器递增）
  static readonly LIB_RESELECT: string = 'libReselect';
  // 书架设置页配置变更信号（计数器递增；设置-书架任意项改动时发布，
  // 常驻挂载的书架页 @Watch 后重读配置即时生效）
  static readonly LIB_SETTINGS_DIRTY: string = 'libSettingsDirty';
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
  // 插件源网络活动信号（计数器递增代表某插件源刚成功完成 API 调用；
  // 插件可能在此时机注入/更新 DNS 直连规则，Index 消费后重试书架封面回填）
  static readonly PLUGIN_NET_TICK: string = 'pluginNetTick';
  static readonly LIB_SELECTION_COUNT: string = 'libSelectionCount';
  // 更新抓取失败章节数（UpdatesPage 徽标）
  static readonly UPDATE_FAILED_COUNT: string = 'updateFailedCount';
  // 备份结果标记（设置页展示上次备份是否失败）
  static readonly LAST_BACKUP_FAILED: string = 'lastBackupFailed';
  // 主页底部页签区高度（px，Index 窗口测量写入）
  static readonly TAB_PAD_H: string = 'tabPadH';
  // 应用锁锁定态（EntryAbility 判定写入，LockOverlay 消费）
  static readonly APP_LOCKED: string = 'appLocked';
  // BT 组件安装引导（DownloadService 失败捕获写入，Index/BtComponentDialog 消费）
  static readonly BT_COMPONENT_ASK: string = 'btComponentAsk';
  // Peer 过滤规则保存信号（计数器递增；BtSettingsPage 消费刷新规则计数）
  static readonly BT_PEER_FILTER_TICK: string = 'btPeerFilterTick';
  // 用户已拒绝 BT 组件安装引导（抑制自动弹窗，手动重试/retryBtComponentTasks 重置）
  static readonly BT_ASK_DISMISSED: string = 'btAskDismissed';
  // 阅读器窄屏手动胶囊模式（ReaderHdsHost 在 HdsTabs 区域宽度 <440vp 时写入；
  // ReaderChapterButton/ReaderMenuIconButton/ReaderPagePill 读取，切换高对比前景色）
  static readonly READER_NARROW_BARS: string = 'readerNarrowBars';
  // Esc 关闭弹层信号（Index 键盘 Esc 广播，计数器递增；各页 @StorageLink + @Watch 消费关闭自身半模态弹层）
  static readonly SHEET_ESC: string = 'sheetEsc';
  // 书库键盘多选信号（Index 根节点按键广播，LibraryPage 消费）：Ctrl+A 全选
  static readonly LIB_SELECT_ALL_REQ: string = 'libSelectAllReq';
  // 书库键盘多选信号：Delete 删除选中（LibraryPage 内部判定选择态，非选择态为空操作）
  static readonly LIB_DELETE_SEL_REQ: string = 'libDeleteSelReq';
  // ===== 首页页签头部桥接（头部已移入 Navigation 标题栏，经 AppStorage 与内容区通信）=====
  // 书库：刷新中（内容区写，头部读 spinner）；搜索框打开（详情页回退搜索时内容区也会写）
  static readonly LIB_REFRESHING: string = 'libRefreshing';
  static readonly LIB_SEARCH_OPEN: string = 'libSearchOpen';
  // 书库：筛选是否生效（内容区写，头部筛选图标着色读）
  static readonly LIB_FILTER_ACTIVE: string = 'libFilterActive';
  // 书库：头部 → 内容区信号（计数器递增触发 @Watch）
  static readonly LIB_FILTER_SHEET_REQ: string = 'libFilterSheetReq';
  static readonly LIB_REFRESH_REQ: string = 'libRefreshReq';
  static readonly LIB_REFRESH_CATEGORY_REQ: string = 'libRefreshCategoryReq';
  static readonly LIB_RANDOM_REQ: string = 'libRandomReq';
  static readonly LIB_SEL_CLEAR_REQ: string = 'libSelClearReq';
  static readonly LIB_SEL_INVERT_REQ: string = 'libSelInvertReq';
  // 更新：刷新中/筛选生效（内容区写，头部读）；头部 → 内容区信号
  static readonly UPDATES_REFRESHING: string = 'updatesRefreshing';
  static readonly UPDATES_FILTER_ACTIVE: string = 'updatesFilterActive';
  static readonly UPDATES_FILTER_SHEET_REQ: string = 'updatesFilterSheetReq';
  static readonly UPDATES_REFRESH_REQ: string = 'updatesRefreshReq';
  // 历史：搜索框打开态（头部持有，页签切换不丢失）；搜索词（头部写，内容区过滤读）；确认清空态（内容区写，头部图标读）；清空请求信号
  static readonly HISTORY_SEARCH_OPEN: string = 'historySearchOpen';
  static readonly HISTORY_SEARCH_QUERY: string = 'historySearchQuery';
  static readonly HISTORY_CONFIRM_CLEAR: string = 'historyConfirmClear';
  static readonly HISTORY_CLEAR_REQ: string = 'historyClearReq';
  // 浏览：当前内部页签（内容区写，头部图标组读）；插件搜索框打开与搜索词（头部写，内容区面板读）
  static readonly BROWSE_CURRENT_TAB: string = 'browseCurrentTab';
  static readonly BROWSE_EXT_SEARCH_OPEN: string = 'browseExtSearchOpen';
  static readonly BROWSE_EXT_QUERY: string = 'browseExtQuery';
  // 浏览：头部 → 内容区信号（图源筛选/插件类型筛选/刷新仓库）
  static readonly BROWSE_SOURCE_FILTER_REQ: string = 'browseSourceFilterReq';
  static readonly BROWSE_EXT_FILTER_REQ: string = 'browseExtFilterReq';
  static readonly BROWSE_REFRESH_REPO_REQ: string = 'browseRefreshRepoReq';
  // 浏览：最近使用源记录版本号（写入源时递增，图源 Tab 监听后重载分组）
  static readonly RECENT_SOURCES_VER: string = 'recentSourcesVer';
}
