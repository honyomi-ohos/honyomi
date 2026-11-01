import { socket } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';

// 极简本地 HTTP 服务：把改写（过滤广告）后的 m3u8 播放列表文本注册到内存，
// AVPlayer 通过 http://127.0.0.1:<port>/<token> 拉取。分片与密钥地址已在播放
// 列表文本内改写为绝对地址，由 AVPlayer 直连 CDN 请求，不经本服务中转。
// 参考 @ohos/video-cache 内部实现（同样基于 TCPSocketServer 自建 HTTP 服务，
// 证明 AVPlayer 接受 127.0.0.1 播放地址）。
export class M3u8ProxyServer {
  // 内存中保留的播放列表条数上限（防泄漏；超出淘汰最早注册的）
  private static readonly MAX_PLAYLISTS: number = 8;
  private static instance: M3u8ProxyServer | null = null;

  private server: socket.TCPSocketServer = socket.constructTCPSocketServerInstance();
  private startPromise: Promise<number> | null = null;
  private port: number = 0;
  private readonly playlists: Map<string, string> = new Map<string, string>();
  private readonly order: string[] = [];
  private tokenSeq: number = 0;

  private constructor() {
  }

  // 注册播放列表文本，返回本地播放地址；启动失败抛出，由调用方回退直连
  static async serve(text: string): Promise<string> {
    const inst: M3u8ProxyServer = M3u8ProxyServer.ensure();
    const port: number = await inst.ensureStarted();
    const token: string = inst.nextToken();
    inst.playlists.set(token, text);
    inst.order.push(token);
    while (inst.order.length > M3u8ProxyServer.MAX_PLAYLISTS) {
      const oldest: string | undefined = inst.order.shift();
      if (oldest !== undefined) {
        inst.playlists.delete(oldest);
      }
    }
    hilog.info(0x0001, 'M3u8Proxy', 'registered %{public}s (%{public}d chars)',
      token, text.length);
    return `http://127.0.0.1:${port}/${token}`;
  }

  private static ensure(): M3u8ProxyServer {
    if (M3u8ProxyServer.instance === null) {
      M3u8ProxyServer.instance = new M3u8ProxyServer();
    }
    return M3u8ProxyServer.instance;
  }

  private nextToken(): string {
    this.tokenSeq += 1;
    return `p${Date.now().toString(36)}${this.tokenSeq.toString(36)}`;
  }

  private ensureStarted(): Promise<number> {
    if (this.startPromise === null) {
      this.startPromise = this.start();
      // 启动失败（端口占用等）时清空缓存的重试，避免永久卡在 rejected Promise
      this.startPromise.catch((): void => {
        this.startPromise = null;
        this.server = socket.constructTCPSocketServerInstance();
      });
    }
    return this.startPromise;
  }

  private async start(): Promise<number> {
    const tryPort: number = Math.round((Math.random() * (65535 - 1024)) + 1024);
    const addr: socket.NetAddress = { address: '127.0.0.1', port: tryPort, family: 1 };
    await this.server.listen(addr);
    // bind 失败时系统会随机分配端口，需读回实际端口
    const local: socket.NetAddress = await this.server.getLocalAddress();
    const bound: number = local.port !== undefined ? local.port : 0;
    this.port = bound > 0 ? bound : tryPort;
    this.server.on('connect', (conn: socket.TCPSocketConnection): void => {
      this.onConnect(conn);
    });
    hilog.info(0x0001, 'M3u8Proxy', 'listening on 127.0.0.1:%{public}d', this.port);
    return this.port;
  }

  private onConnect(conn: socket.TCPSocketConnection): void {
    conn.on('message', (info: socket.SocketMessageInfo): void => {
      this.handleRequest(conn, info.message);
    });
    conn.on('close', (): void => {
      this.detachConn(conn);
    });
    conn.on('error', (_err: Error): void => {
      this.detachConn(conn);
    });
  }

  private async handleRequest(conn: socket.TCPSocketConnection, msg: ArrayBuffer): Promise<void> {
    let req: string = this.asciiHead(msg, 256);
    const lineEnd: number = req.indexOf('\r\n');
    if (lineEnd >= 0) {
      req = req.substring(0, lineEnd);
    }
    const parts: string[] = req.split(' ');
    let token: string = '';
    if (parts.length >= 2 && parts[0] === 'GET') {
      token = parts[1];
    }
    const q: number = token.indexOf('?');
    if (q >= 0) {
      token = token.substring(0, q);
    }
    if (token.startsWith('/')) {
      token = token.substring(1);
    }
    const text: string | undefined = this.playlists.get(token);
    const status: string = text !== undefined ? '200 OK' : '404 Not Found';
    const body: Uint8Array = util.TextEncoder.create('utf-8')
      .encodeInto(text !== undefined ? text : '');
    const header: string =
      `HTTP/1.1 ${status}\r\n` +
      'Content-Type: application/vnd.apple.mpegurl\r\n' +
      `Content-Length: ${body.byteLength}\r\n` +
      'Connection: close\r\n' +
      '\r\n';
    try {
      const headerOpt: socket.TCPSendOptions = { data: header };
      await conn.send(headerOpt);
      if (body.byteLength > 0) {
        const bodyBuf: ArrayBuffer = new ArrayBuffer(body.byteLength);
        new Uint8Array(bodyBuf).set(body);
        const bodyOpt: socket.TCPSendOptions = { data: bodyBuf };
        await conn.send(bodyOpt);
      }
    } catch (e) {
      hilog.warn(0x0001, 'M3u8Proxy', 'send failed: %{public}s', `${e}`);
    }
    this.detachConn(conn);
  }

  private detachConn(conn: socket.TCPSocketConnection): void {
    try {
      conn.off('message');
      conn.off('close');
      conn.off('error');
      conn.close();
    } catch (_e) {
      // 已关闭
    }
  }

  // 请求行按 ASCII 解码（HTTP 请求行保证 ASCII，无需构造 TextDecoder）
  private asciiHead(buf: ArrayBuffer, maxLen: number): string {
    const bytes: Uint8Array = new Uint8Array(buf);
    const n: number = Math.min(bytes.length, maxLen);
    let s: string = '';
    for (let i = 0; i < n; i++) {
      s += String.fromCharCode(bytes[i]);
    }
    return s;
  }
}
