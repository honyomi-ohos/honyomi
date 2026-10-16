import { http, connection } from '@kit.NetworkKit';
import { Settings } from '../common/Settings';
import { Log } from '../common/Log';

const TAG = 'Doh';

// DoH 供应商（RFC 8484 标准 wire-format 端点，对齐 Mihon PREF_DOH 列表）
export interface DohProvider {
  id: string;
  label: string;
  url: string;
}

// DNS 应答解析结果：IPv4 列表 + 最小 TTL（秒）
interface DohAnswer {
  ips: string[];
  ttl: number;
}

// host → 已注入 netstack 的映射缓存
interface DohCacheEntry {
  ips: string[];
  expireAt: number;
}

// DNS over HTTPS 解析器：
// - 开启后对每个新 host 先经所选供应商做 RFC 8484 查询，再以
//   connection.addCustomDnsRule 注入应用 netstack（应用内所有请求生效，
//   含下载与系统 Image 网络栈）
// - 查询走独立裸 http 通道（不经 Http/CookieJar/UA 管线，天然免递归）
// - 解析失败 fail-open：不注入规则，回落系统 DNS，绝不阻断业务请求
// - 结果缓存至 TTL 过期（钳制 60s - 1h），并发去重
export class Doh {
  // 供应商清单（顺序即设置页展示顺序）
  static readonly PROVIDERS: DohProvider[] = [
    { id: 'cloudflare', label: 'Cloudflare', url: 'https://cloudflare-dns.com/dns-query' },
    { id: 'google', label: 'Google', url: 'https://dns.google/dns-query' },
    { id: 'adguard', label: 'AdGuard', url: 'https://dns.adguard-dns.com/dns-query' },
    { id: 'quad9', label: 'Quad9', url: 'https://dns.quad9.net/dns-query' },
    { id: 'alidns', label: 'AliDNS', url: 'https://dns.alidns.com/dns-query' },
    { id: 'dnspod', label: 'DNSPod', url: 'https://doh.pub/dns-query' },
    { id: '360', label: '360', url: 'https://doh.360.cn/dns-query' },
    { id: 'quad101', label: 'Quad 101', url: 'https://dns.twnic.tw/dns-query' },
    { id: 'mullvad', label: 'Mullvad', url: 'https://dns.mullvad.net/dns-query' },
    { id: 'controld', label: 'Control D', url: 'https://freedom.dns.controld.com/dns-query' },
    { id: 'njalla', label: 'Njalla', url: 'https://dns.njal.la/dns-query' },
    { id: 'shecan', label: 'Shecan', url: 'https://free.shecan.ir/dns-query' },
  ];

  private static cache: Map<string, DohCacheEntry> = new Map();
  private static inflight: Map<string, Promise<void>> = new Map();
  private static querySeq: number = 1;

  // 当前生效供应商（设置未开启时 undefined）
  static currentProvider(): DohProvider | undefined {
    const id: string = Settings.getDohProvider();
    if (id === '') {
      return undefined;
    }
    return Doh.providerOf(id);
  }

  static providerOf(id: string): DohProvider | undefined {
    for (const p of Doh.PROVIDERS) {
      if (p.id === id) {
        return p;
      }
    }
    return undefined;
  }

  // 请求前调用：确保 host 的 DoH 映射已注入（失败静默回落系统 DNS）
  static async prepare(url: string): Promise<void> {
    const provider = Doh.currentProvider();
    if (provider === undefined) {
      return;
    }
    const host = Doh.hostOf(url);
    if (host === '' || Doh.isIpLiteral(host)) {
      return;
    }
    const now = Date.now();
    const hit = Doh.cache.get(host);
    if (hit !== undefined && hit.expireAt > now) {
      return;
    }
    const pending = Doh.inflight.get(host);
    if (pending !== undefined) {
      await pending;
      return;
    }
    const job = Doh.resolveAndRegister(host, provider).then((): void => {
      Doh.inflight.delete(host);
    }).catch((): void => {
      Doh.inflight.delete(host);
    });
    Doh.inflight.set(host, job);
    await job;
  }

  // 关闭/切换供应商时清空全部自定义规则与缓存（规则仅进程内有效，重启即失）
  static reset(): void {
    Doh.cache.clear();
    try {
      connection.clearCustomDnsRules();
    } catch (e) {
      Log.debug(TAG, `clearCustomDnsRules failed: ${e}`);
    }
  }

  private static async resolveAndRegister(host: string, provider: DohProvider): Promise<void> {
    const answer = await Doh.resolve(host, provider);
    if (answer === undefined || answer.ips.length === 0) {
      Log.debug(TAG, `resolve ${host} via ${provider.id} got no answer`);
      return;
    }
    await connection.addCustomDnsRule(host, answer.ips);
    const ttlMs: number = Math.min(Math.max(answer.ttl, 60), 3600) * 1000;
    const entry: DohCacheEntry = { ips: answer.ips, expireAt: Date.now() + ttlMs };
    Doh.cache.set(host, entry);
    Log.debug(TAG, `${host} -> ${answer.ips.join(',')} via ${provider.id} ttl=${answer.ttl}`);
  }

  // RFC 8484：POST application/dns-message（单问题 A 查询）
  private static async resolve(host: string, provider: DohProvider): Promise<DohAnswer | undefined> {
    const id = (Doh.querySeq++) & 0xffff;
    const query = Doh.buildQuery(id, host);
    const client: http.HttpRequest = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/dns-message',
          'Accept': 'application/dns-message'
        },
        extraData: query.buffer,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 5000,
        readTimeout: 5000,
      };
      const resp = await client.request(provider.url, options);
      if (resp.responseCode < 200 || resp.responseCode >= 300 || typeof resp.result !== 'object') {
        return undefined;
      }
      return Doh.parseAnswer(new Uint8Array(resp.result as ArrayBuffer));
    } finally {
      client.destroy();
    }
  }

  // DNS 报文构造：12 字节头 + QNAME + QTYPE(A)/QCLASS(IN)
  private static buildQuery(id: number, host: string): Uint8Array {
    const labels: string[] = host.split('.');
    let qnameLen = 1;
    for (const label of labels) {
      qnameLen += label.length + 1;
    }
    const buf = new ArrayBuffer(12 + qnameLen + 4);
    const view = new Uint8Array(buf);
    view[0] = (id >>> 8) & 0xff;
    view[1] = id & 0xff;
    view[2] = 0x01; // RD
    view[3] = 0x00;
    view[5] = 1; // QDCOUNT = 1
    let off = 12;
    for (const label of labels) {
      view[off] = label.length;
      off++;
      for (let i = 0; i < label.length; i++) {
        view[off] = label.charCodeAt(i) & 0xff;
        off++;
      }
    }
    view[off] = 0; // 根标签
    off++;
    view[off] = 0;
    view[off + 1] = 1; // QTYPE = A
    view[off + 2] = 0;
    view[off + 3] = 1; // QCLASS = IN
    return view;
  }

  // 应答解析：跳过问题区，遍历应答区取 A 记录 IPv4 与最小 TTL
  private static parseAnswer(msg: Uint8Array): DohAnswer | undefined {
    if (msg.length < 12) {
      return undefined;
    }
    const qdcount = (msg[4] << 8) | msg[5];
    const ancount = (msg[6] << 8) | msg[7];
    let off = 12;
    for (let i = 0; i < qdcount && off < msg.length; i++) {
      off = Doh.skipName(msg, off);
      if (off < 0 || off + 4 > msg.length) {
        return undefined;
      }
      off += 4; // QTYPE + QCLASS
    }
    const ips: string[] = [];
    let minTtl = 3600;
    for (let i = 0; i < ancount && off < msg.length; i++) {
      off = Doh.skipName(msg, off);
      if (off < 0 || off + 10 > msg.length) {
        break;
      }
      const type = (msg[off] << 8) | msg[off + 1];
      const ttl = Doh.readU32(msg, off + 4);
      const rdlength = (msg[off + 8] << 8) | msg[off + 9];
      off += 10;
      if (off + rdlength > msg.length) {
        break;
      }
      if (type === 1 && rdlength === 4) {
        ips.push(`${msg[off]}.${msg[off + 1]}.${msg[off + 2]}.${msg[off + 3]}`);
        if (ttl > 0 && ttl < minTtl) {
          minTtl = ttl;
        }
      }
      off += rdlength;
    }
    const answer: DohAnswer = { ips: ips, ttl: minTtl };
    return answer;
  }

  // 跳过 NAME 字段：压缩指针占 2 字节；标签序列以 0 结束。返回新偏移，越界 -1
  private static skipName(msg: Uint8Array, off: number): number {
    let p = off;
    while (p < msg.length) {
      const len = msg[p];
      if ((len & 0xc0) === 0xc0) {
        return p + 2;
      }
      if (len === 0) {
        return p + 1;
      }
      p += len + 1;
    }
    return -1;
  }

  private static readU32(msg: Uint8Array, off: number): number {
    return ((msg[off] << 24) | (msg[off + 1] << 16) | (msg[off + 2] << 8) | msg[off + 3]) >>> 0;
  }

  // 从 URL 提取主机名（剥离协议/端口/路径/凭据）
  private static hostOf(url: string): string {
    let s = url;
    if (s.indexOf('https://') === 0) {
      s = s.substring(8);
    } else if (s.indexOf('http://') === 0) {
      s = s.substring(7);
    } else {
      return '';
    }
    const slash = s.indexOf('/');
    if (slash >= 0) {
      s = s.substring(0, slash);
    }
    const colon = s.indexOf(':');
    if (colon >= 0) {
      s = s.substring(0, colon);
    }
    const at = s.indexOf('@');
    if (at >= 0) {
      s = s.substring(at + 1);
    }
    return s.toLowerCase();
  }

  // 纯数字点分（IPv4 字面量）无需 DoH 解析
  private static isIpLiteral(host: string): boolean {
    if (host.indexOf(':') >= 0) {
      return true;
    }
    for (let i = 0; i < host.length; i++) {
      const c = host.charAt(i);
      if (c !== '.' && (c < '0' || c > '9')) {
        return false;
      }
    }
    return host.length > 0;
  }
}
