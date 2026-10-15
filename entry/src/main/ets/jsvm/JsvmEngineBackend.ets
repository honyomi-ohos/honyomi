/*
 * JsvmEngineBackend — EngineBackend 契约的 JSVM 引擎实现。
 *
 * 本模块位于 native 依赖链上（JsvmExtensionManager → NativeHttpBridge →
 * libjsvmengine.so），只允许 EntryAbility 等页面模块图之外的入口导入；
 * UI/服务层一律经 EngineGateway 间接访问，保证页面导入链 native-free
 * （预览器可正常渲染）。
 */

import { JsvmExtensionManager } from './JsvmExtensionManager';
import { EngineBackend, JsvmExtensionInfo } from './EngineGateway';

export class JsvmEngineBackend implements EngineBackend {
  init(): void {
    JsvmExtensionManager.init();
  }

  loadExtension(key: string, code: string, seed: string): Promise<JsvmExtensionInfo> {
    return JsvmExtensionManager.loadExtension(key, code, seed);
  }

  unloadExtension(key: string): Promise<void> {
    return JsvmExtensionManager.unloadExtension(key);
  }

  callData<T>(key: string, method: string, args: Array<string | number | boolean | object>): Promise<T> {
    return JsvmExtensionManager.callData<T>(key, method, args);
  }

  memoryBytes(key: string): number {
    return JsvmExtensionManager.memoryBytes(key);
  }
}
