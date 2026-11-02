import { KeyCode } from '@kit.InputKit';

// 键盘/音量键路由动作：两阅读器共用的按键骨架，页面差异（守卫条件/翻页入口/
// 字号与跳边支持性）经函数字段注入（aboutToAppear 接线）。
// 注：不能用接口 + 对象字面量初始化——ArkTS 禁止带函数成员的对象字面量
// （arkts-no-untyped-obj-literals），故以函数字段类 + 默认空实现承载
export class ReaderKeyActions {
  // 音量键翻页守卫（含开关/加载/正文/菜单/弹层等页面条件）
  volumeTurnReady: () => boolean = (): boolean => false;
  isLoading: () => boolean = (): boolean => false;
  // ESC 逐级关闭最上层弹层（Sheet 等），有关闭返回 true
  dismissTopLayer: () => boolean = (): boolean => false;
  isMenuOpen: () => boolean = (): boolean => false;
  closeMenu: () => void = (): void => {};
  // ENTER 呼出菜单的页面条件（小说要求正文非空）
  canToggleMenu: () => boolean = (): boolean => false;
  toggleMenu: () => void = (): void => {};
  // Ctrl +/- 字号调节（仅小说）
  supportsFontShortcut: () => boolean = (): boolean => false;
  adjustFont: (delta: number) => void = (_delta: number): void => {};
  // Home/End 跳本章首/末页（仅漫画）
  supportsHomeEnd: () => boolean = (): boolean => false;
  jumpEdge: (toEnd: boolean) => void = (_toEnd: boolean): void => {};
  // 阅读方向：下一页在左侧（RTL）时右方向键=上一页
  dpadNextOnLeft: () => boolean = (): boolean => false;
  // 方向键上下是否映射为滚动（小说滚动模式/漫画竖向与条漫）
  dpadScrolls: () => boolean = (): boolean => false;
  // 翻页统一入口（各自 keyTurn）
  turn: (delta: number) => void = (_delta: number): void => {};
  exit: () => void = (): void => {};
}

// 键盘控制路由（外接键盘/PC）：音量键翻页、ESC 逐级退出、回车呼出菜单、
// Ctrl+/- 字号、Home/End 跳边、PgUp/PgDn/空格/方向键翻页
export class ReaderKeyRouter {
  static handle(event: KeyEvent, actions: ReaderKeyActions): void {
    if (event.type !== KeyType.Down) {
      return;
    }
    // 音量键翻页：守卫不满足也不落入后续分支（等效原实现提前 return）
    if (event.keyCode === KeyCode.KEYCODE_VOLUME_UP || event.keyCode === KeyCode.KEYCODE_VOLUME_DOWN) {
      if (actions.volumeTurnReady()) {
        actions.turn(event.keyCode === KeyCode.KEYCODE_VOLUME_UP ? -1 : 1);
      }
      return;
    }
    if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
      // 加载中由 LoadingBackButton 的 ESC 快捷键兜底退出，避免重复 pop
      if (actions.isLoading()) {
        return;
      }
      if (actions.dismissTopLayer()) {
        return;
      }
      if (actions.isMenuOpen()) {
        actions.closeMenu();
        return;
      }
      actions.exit();
      return;
    }
    if (event.keyCode === KeyCode.KEYCODE_ENTER) {
      if (!actions.isLoading() && actions.canToggleMenu()) {
        actions.toggleMenu();
      }
      return;
    }
    // Ctrl +/-（含小键盘）：字号调节，与文本设置面板滑杆同范围
    const ctrlDown: boolean = event.getModifierKeyState !== undefined && event.getModifierKeyState(['Ctrl']);
    if (ctrlDown && (event.keyCode === KeyCode.KEYCODE_EQUALS || event.keyCode === KeyCode.KEYCODE_NUMPAD_ADD)) {
      if (actions.supportsFontShortcut()) {
        actions.adjustFont(1);
      }
      return;
    }
    if (ctrlDown && (event.keyCode === KeyCode.KEYCODE_MINUS || event.keyCode === KeyCode.KEYCODE_NUMPAD_SUBTRACT)) {
      if (actions.supportsFontShortcut()) {
        actions.adjustFont(-1);
      }
      return;
    }
    // Home/End：跳本章首页/末页
    if (event.keyCode === KeyCode.KEYCODE_MOVE_HOME) {
      if (actions.supportsHomeEnd()) {
        actions.jumpEdge(false);
      }
      return;
    }
    if (event.keyCode === KeyCode.KEYCODE_MOVE_END) {
      if (actions.supportsHomeEnd()) {
        actions.jumpEdge(true);
      }
      return;
    }
    let delta: number = 0;
    if (event.keyCode === KeyCode.KEYCODE_PAGE_DOWN || event.keyCode === KeyCode.KEYCODE_SPACE) {
      delta = 1;
    } else if (event.keyCode === KeyCode.KEYCODE_PAGE_UP) {
      delta = -1;
    } else if (event.keyCode === KeyCode.KEYCODE_DPAD_RIGHT) {
      delta = actions.dpadNextOnLeft() ? -1 : 1;
    } else if (event.keyCode === KeyCode.KEYCODE_DPAD_LEFT) {
      delta = actions.dpadNextOnLeft() ? 1 : -1;
    } else if (event.keyCode === KeyCode.KEYCODE_DPAD_DOWN) {
      delta = actions.dpadScrolls() ? 1 : 0;
    } else if (event.keyCode === KeyCode.KEYCODE_DPAD_UP) {
      delta = actions.dpadScrolls() ? -1 : 0;
    }
    if (delta !== 0) {
      actions.turn(delta);
    }
  }
}
