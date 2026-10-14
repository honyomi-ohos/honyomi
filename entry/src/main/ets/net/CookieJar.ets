import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0002;
const TAG = 'CookieJar';

// 单条 Cookie：值 + 过期时间戳（毫秒，0 表示会话期不过期）+ Secure 标记
interface CookieEntry {
  value: string;
  expires: number;
  secure: boolean;
}

interface PersistShape {
  domains?: Record<string, Record<string, CookieEntry>>;
}

// 域名级 Cookie 存储：自动回收响应 Set-Cookie 并持久化，请求时自动附带
// （插件 $.http、图片管线、下载服务全部经此受益；cf_clearance 亦存放于此）
export class CookieJar {
  private static jar: Map<string, Record<string, CookieEntry>> = new Map();
  private static filePath: string = '';
  private static saveTimer: number = -1;

  static init(context: common.UIAbilityContext): void {
    CookieJar.filePath = `${context.filesDir}/cookies.json`;
    try {
      if (fs.accessSync(CookieJar.filePath)) {
        const raw = JSON.parse(fs.readTextSync(CookieJar.filePath)) as PersistShape;
        const domains = raw.domains;
        if (domains !== undefined) {
          const keys = Object.keys(domains);
          for (const d of keys) {
            const rawEntries = domains[d] as Record<string, Object>;
            if (rawEntries === undefined || rawEntries === null) {
              continue;
            }
            CookieJar.jar.set(d, CookieJar.normalizeEntries(rawEntries));
          }
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'load failed: %{public}s', (e as Error).message);
    }
  }

  // 兼容旧持久化格式（cookie 值为纯字符串）与新格式（CookieEntry）
  private static normalizeEntries(rawEntries: Record<string, Object>): Record<string, CookieEntry> {
    const out: Record<string, CookieEntry> = {};
    const names = Object.keys(rawEntries);
    for (const n of names) {
      const v = rawEntries[n];
      if (typeof v === 'string') {
        const legacy: CookieEntry = { value: v as string, expires: 0, secure: false };
        out[n] = legacy;
      } else if (v !== undefined && v !== null) {
        const entry = v as CookieEntry;
        if (typeof entry.value === 'string') {
          const normalized: CookieEntry = {
            value: entry.value,
            expires: typeof entry.expires === 'number' ? entry.expires : 0,
            secure: entry.secure === true,
          };
          out[n] = normalized;
        }
      }
    }
    return out;
  }

  // 提取 url 的 host（小写、去端口）
  static hostOf(url: string): string {
    const i = url.indexOf('://');
    if (i < 0) {
      return '';
    }
    let rest = url.substring(i + 3);
    const at = rest.indexOf('@');
    if (at >= 0) {
      rest = rest.substring(at + 1);
    }
    let end = rest.length;
    const slash = rest.indexOf('/');
    if (slash >= 0 && slash < end) {
      end = slash;
    }
    const q = rest.indexOf('?');
    if (q >= 0 && q < end) {
      end = q;
    }
    const hash = rest.indexOf('#');
    if (hash >= 0 && hash < end) {
      end = hash;
    }
    let host = rest.substring(0, end).toLowerCase();
    const colon = host.indexOf(':');
    if (colon >= 0) {
      host = host.substring(0, colon);
    }
    return host;
  }

  // 汇总适用于 url 的 Cookie 请求头（host 精确匹配或父域后缀匹配；
  // 过滤已过期条目，Secure cookie 仅经 https 携带）
  static headerFor(url: string): string {
    const host = CookieJar.hostOf(url);
    if (host === '') {
      return '';
    }
    const https = url.indexOf('https://') === 0;
    const now = Date.now();
    const parts: string[] = [];
    CookieJar.jar.forEach((cookies: Record<string, CookieEntry>, domain: string) => {
      if (host === domain || host.endsWith(`.${domain}`)) {
        const names = Object.keys(cookies);
        for (const name of names) {
          const entry = cookies[name];
          if (entry.expires > 0 && entry.expires <= now) {
            continue;
          }
          if (entry.secure && !https) {
            continue;
          }
          parts.push(`${name}=${entry.value}`);
        }
      }
    });
    return parts.join('; ');
  }

  // 判断 url 域下是否已存有指定名称的 Cookie（如 cf_clearance；过期条目视为不存在）
  static hasCookie(url: string, name: string): boolean {
    const host = CookieJar.hostOf(url);
    if (host === '') {
      return false;
    }
    let found = false;
    const now = Date.now();
    CookieJar.jar.forEach((cookies: Record<string, CookieEntry>, domain: string) => {
      if (found || (host !== domain && !host.endsWith(`.${domain}`))) {
        return;
      }
      const names = Object.keys(cookies);
      for (const n of names) {
        if (n === name) {
          const entry = cookies[n];
          if (entry.expires > 0 && entry.expires <= now) {
            continue;
          }
          found = true;
          return;
        }
      }
    });
    return found;
  }

  // 解析 OHOS http 响应头对象中的 Set-Cookie（可能为 string 或 string[]）
  static storeFromResponse(url: string, header: Object): void {
    const h = header as Record<string, Object>;
    const keys = Object.keys(h);
    for (const k of keys) {
      if (k.toLowerCase() !== 'set-cookie') {
        continue;
      }
      const v = h[k];
      if (typeof v === 'string') {
        CookieJar.storeOne(url, v);
      } else if (Array.isArray(v)) {
        const list = v as string[];
        for (const s of list) {
          CookieJar.storeOne(url, s);
        }
      }
    }
  }

  // 导入 ArkWeb cookie 字符串（"a=1; b=2" 形态，如 CF 验证页收割）
  static importCookieString(url: string, cookieStr: string): void {
    const host = CookieJar.hostOf(url);
    if (host === '' || cookieStr === '') {
      return;
    }
    const https = url.indexOf('https://') === 0;
    const parts = cookieStr.split(';');
    for (const part of parts) {
      const p = part.trim();
      const eq = p.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      const imported: CookieEntry = {
        value: p.substring(eq + 1).trim(),
        expires: 0,
        secure: https,
      };
      CookieJar.put(host, p.substring(0, eq).trim(), imported);
    }
  }

  // 解析并保存单个 Set-Cookie 值（识别 Domain / Max-Age / Expires / Secure 属性）。
  // Domain 归属校验：仅当 Domain 等于请求 host 或其父域（且非公共后缀本身）时接受，
  // 否则丢弃该 cookie，防止任意站点跨域种植/污染 cf_clearance 等凭证。
  static storeOne(url: string, setCookie: string): void {
    const segments = setCookie.split(';');
    const first = segments[0].trim();
    const eq = first.indexOf('=');
    if (eq <= 0) {
      return;
    }
    const name = first.substring(0, eq).trim();
    const value = first.substring(eq + 1).trim();
    if (name === '') {
      return;
    }
    const requestHost = CookieJar.hostOf(url);
    if (requestHost === '') {
      return;
    }
    let domain = requestHost;
    let domainGiven = false;
    let expired = false;
    let expires = 0;
    let secure = false;
    for (let i = 1; i < segments.length; i++) {
      const seg = segments[i].trim();
      const lower = seg.toLowerCase();
      if (lower.indexOf('domain=') === 0) {
        domainGiven = true;
        domain = seg.substring(7).trim().toLowerCase();
        if (domain.startsWith('.')) {
          domain = domain.substring(1);
        }
      } else if (lower.indexOf('max-age=') === 0) {
        const seconds = parseInt(seg.substring(8).trim(), 10);
        if (!isNaN(seconds)) {
          if (seconds <= 0) {
            expired = true;
          } else {
            expires = Date.now() + seconds * 1000;
          }
        }
      } else if (lower.indexOf('expires=') === 0) {
        const t = Date.parse(seg.substring(8).trim());
        if (!isNaN(t)) {
          if (t <= Date.now()) {
            expired = true;
          } else {
            expires = t;
          }
        }
      } else if (lower === 'secure') {
        secure = true;
      }
    }
    if (domainGiven) {
      // 仅接受 host 本身或其父域；父域不得是公共后缀本身
      const isSelf = domain === requestHost;
      const isParent = domain !== '' && requestHost.endsWith(`.${domain}`);
      if (!isSelf && !isParent) {
        return;
      }
      if (CookieJar.isPublicSuffix(domain)) {
        return;
      }
    }
    if (domain === '') {
      return;
    }
    if (expired) {
      CookieJar.remove(domain, name);
      return;
    }
    const entry: CookieEntry = { value: value, expires: expires, secure: secure };
    CookieJar.put(domain, name, entry);
  }

  // 极简公共后缀判定：单标签域名与常见多标签公共后缀视为公共后缀
  // （完整 PSL 过重，此处覆盖典型滥用路径即可）
  private static isPublicSuffix(domain: string): boolean {
    if (domain.indexOf('.') < 0) {
      return true;
    }
    const suffixes: string[] = [
      'com.cn', 'net.cn', 'org.cn', 'gov.cn', 'edu.cn', 'ac.cn',
      'co.uk', 'org.uk', 'ac.uk', 'gov.uk',
      'co.jp', 'or.jp', 'ne.jp', 'ac.jp', 'go.jp',
      'com.au', 'net.au', 'org.au', 'edu.au',
      'co.kr', 'or.kr', 'co.tw', 'com.tw', 'org.tw',
      'com.hk', 'com.sg', 'com.my', 'co.in', 'co.nz',
      'com.br', 'com.mx', 'com.ar', 'co.za', 'com.tr',
      'com.ru', 'net.ru', 'org.ru',
    ];
    return suffixes.indexOf(domain) >= 0;
  }

  static clear(): void {
    CookieJar.jar.clear();
    CookieJar.save();
  }

  // ---------------- 内部实现 ----------------

  private static put(domain: string, name: string, entry: CookieEntry): void {
    let cookies = CookieJar.jar.get(domain);
    if (cookies === undefined) {
      const fresh: Record<string, CookieEntry> = {};
      CookieJar.jar.set(domain, fresh);
      cookies = fresh;
    }
    cookies[name] = entry;
    CookieJar.scheduleSave();
  }

  private static remove(domain: string, name: string): void {
    const cookies = CookieJar.jar.get(domain);
    if (cookies === undefined) {
      return;
    }
    const kept: Record<string, CookieEntry> = {};
    const names = Object.keys(cookies);
    for (const n of names) {
      if (n !== name) {
        kept[n] = cookies[n];
      }
    }
    if (Object.keys(kept).length === 0) {
      CookieJar.jar.delete(domain);
    } else {
      CookieJar.jar.set(domain, kept);
    }
    CookieJar.scheduleSave();
  }

  private static scheduleSave(): void {
    if (CookieJar.saveTimer >= 0) {
      clearTimeout(CookieJar.saveTimer);
    }
    CookieJar.saveTimer = setTimeout(() => {
      CookieJar.saveTimer = -1;
      CookieJar.save();
    }, 500);
  }

  // 原子持久化：先写临时文件，再 rename 原子替换主文件；
  // rename 不支持覆盖时移除旧文件后重试，避免写中途崩溃损坏 cookies.json
  private static save(): void {
    if (CookieJar.filePath === '') {
      return;
    }
    const tmpPath = `${CookieJar.filePath}.tmp`;
    try {
      const domains: Record<string, Record<string, CookieEntry>> = {};
      CookieJar.jar.forEach((cookies: Record<string, CookieEntry>, domain: string) => {
        domains[domain] = cookies;
      });
      const shape: PersistShape = { domains: domains };
      const file = fs.openSync(tmpPath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, JSON.stringify(shape));
      } finally {
        fs.closeSync(file);
      }
      try {
        fs.renameSync(tmpPath, CookieJar.filePath);
      } catch (e) {
        try {
          if (fs.accessSync(CookieJar.filePath)) {
            fs.unlinkSync(CookieJar.filePath);
          }
        } catch (e2) {
          // 旧主文件不存在，直接 rename
        }
        fs.renameSync(tmpPath, CookieJar.filePath);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'save failed: %{public}s', (e as Error).message);
    }
  }
}
