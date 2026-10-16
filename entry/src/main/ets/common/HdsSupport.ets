// 全局 HDS 可用性探测（Index 首页 / 阅读器共用）：
// HDS 组件（@kit.UIDesignKit）由系统 HDS 运行时注册，无 HDS 运行时环境（预览器等）
// HdsTabs 为 null。模块加载时一次判定并缓存，运行期永不变化——各页面据此做
// if/else 降级，分支不会中途翻转（翻转会整体卸载重建子树、丢失页面状态）。
import { deviceInfo } from '@kit.BasicServicesKit';
import { HdsTabs } from '@kit.UIDesignKit';

const HDS_RUNTIME_AVAILABLE: boolean = HdsTabs !== null && HdsTabs !== undefined;

// PC/2in1 排除依据：HDS 主题模式资源在 2in1 上缺失（hmos_hds_tab_pattern 缺失致
// 原生崩溃），桌面设备统一走回退路径
const PC_LIKE_DEVICE: boolean = deviceInfo.deviceType === '2in1' || deviceInfo.deviceType === 'pc';

// HDS 运行时是否可用：仅探测运行时注册，不区分设备形态（首页窄屏 HdsTabs 用）
export function isHdsRuntimeAvailable(): boolean {
  return HDS_RUNTIME_AVAILABLE;
}
