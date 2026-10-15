/*
 * EngineGateway — native-free seam between the UI/service layer and the
 * JSVM extension engine.
 *
 * UI 页面与服务层（PluginService / JsvmSource / pages/*）只依赖本模块：
 * 这里没有任何 libjsvmengine.so 导入，预览器加载页面时不会把 native
 * 库拉进模块图。真正的引擎实现（JsvmEngineBackend → JsvmExtensionManager
 * → NativeHttpBridge → libjsvmengine.so）由 EntryAbility 启动时注册，
 * 预览器等无 Ability 环境 backend 为空，各调用方优雅降级。
 */

/** 加载完成后的引擎能力信息（EngineBackend.loadExtension 返回）。 */
export interface JsvmExtensionInfo {
  key: string;
  kind: string; // 'tachiyomi' | 'simple'
  methods: string[];
}

/** JSVM 引擎后端契约：UI/服务层只接触本接口，不接触任何 native 模块。 */
export interface EngineBackend {
  /** 安装 HTTP 桥（幂等），须在首个插件网络请求前调用。 */
  init(): void;
  /** 拉起专属 Worker + 隔离 JSVM_Context 并执行插件脚本，探测适配器能力。 */
  loadExtension(key: string, code: string, seed: string): Promise<JsvmExtensionInfo>;
  /** 卸载插件并释放 Worker + JSVM 引擎。 */
  unloadExtension(key: string): Promise<void>;
  /** 插件引擎当前是否处于已加载且可用状态（LRU 淘汰/卸载后返回 false）。 */
  isLoaded(key: string): boolean;
  /**
   * 调用插件规范化方法，返回适配器 envelope 的 `data` 载荷。
   * Cloudflare 质询时抛出 WebChallengeError。
   */
  callData<T>(key: string, method: string, args: Array<string | number | boolean | object>): Promise<T>;
  /** 插件引擎最近一次上报的 JS 堆用量（字节；未知返回 -1）。 */
  memoryBytes(key: string): number;
}

/**
 * Cloudflare 质询异常：源站返回 401/403/503 盾页时由引擎上抛，
 * ArkTS 层捕获后打开单实例验证 webview，收割 token 后重试。
 */
export class WebChallengeError extends Error {
  readonly challengeUrl: string;

  constructor(url: string) {
    super('cf_required');
    this.challengeUrl = url;
  }
}

/** Bridge error 字段内的质询标记前缀。 */
const CHALLENGE_PREFIX = 'CF_CHALLENGE:';

/** 判断 envelope error 字符串是否为质询异常。 */
export function isChallengeError(error: string): boolean {
  return error.indexOf(CHALLENGE_PREFIX) === 0;
}

/** 从 envelope error 字符串提取质询 URL。 */
export function challengeUrlOf(error: string): string {
  return error.substring(CHALLENGE_PREFIX.length);
}

/** 构造经 bridge 上报的质询标记 error 字符串。 */
export function challengeError(url: string): string {
  return `${CHALLENGE_PREFIX}${url}`;
}

/**
 * 引擎后端注册中心。EntryAbility.onCreate 注册 JsvmEngineBackend；
 * 预览器环境（无 Ability 生命周期）不注册，页面渲染零 native 依赖。
 */
export class EngineGateway {
  private static backend: EngineBackend | undefined = undefined;

  static setBackend(backend: EngineBackend): void {
    EngineGateway.backend = backend;
  }

  static get(): EngineBackend | undefined {
    return EngineGateway.backend;
  }

  /** 取后端，未注册时抛 engine_unavailable（预览器/引擎不可用场景）。 */
  static require(): EngineBackend {
    if (EngineGateway.backend === undefined) {
      throw new Error('engine_unavailable');
    }
    return EngineGateway.backend;
  }
}
