// 翻译引擎统一接口：各引擎实现批量翻译（返回数组与入参一一对应），
// 由 TranslationService 按优先级串联、失败回退下一家
export interface TranslationProvider {
  // 引擎 id（持久化优先级排序 / 密钥归属）
  id: string;
  // 引擎是否已配置可用（密钥齐全；免费引擎恒 true）
  isConfigured(): boolean;
  // 该引擎是否支持此翻译方向（不支持则整链跳过，回退下一家）
  supports(from: string, to: string): boolean;
  // 批量翻译：失败 reject Error（message 带 engine_ 前缀便于定位）
  translate(texts: string[], from: string, to: string): Promise<string[]>;
}
