// EPUB 解析：container.xml → OPF（manifest/spine/metadata/封面）→ 章节文件读取，
// 章节内相对引用重写为解压目录 file:// 绝对路径（不复制资源）。
// 输入为 zlib.decompressFile 已解压目录；纯逻辑无 UI 依赖，taskpool 可用。

import { BookFileIo, BookTextCodec } from './ByteUtils';

export class EpubBookResult {
  title: string = '';
  author: string = '';
  chapters: string[] = [];
  chapterNames: string[] = [];
  coverPath: string = '';
}

// manifest 条目
class ManifestItem {
  id: string = '';
  href: string = '';
  mediaType: string = '';
  properties: string = '';
}

export class EpubParser {
  // 主入口：extractDir = epub 解压根目录
  static parse(extractDir: string): EpubBookResult {
    const containerPath = `${extractDir}/META-INF/container.xml`;
    const container = BookFileIo.readText(containerPath);
    if (container === null) {
      throw new Error('invalid_epub_container');
    }
    const opfMatch = /<rootfile[^>]+full-path\s*=\s*["']([^"']+)["']/i.exec(container);
    if (opfMatch === null) {
      throw new Error('invalid_epub_container');
    }
    const opfPath = EpubParser.joinPath(extractDir, opfMatch[1]);
    const opf = BookFileIo.readText(opfPath);
    if (opf === null) {
      throw new Error('invalid_epub_opf');
    }
    const opfDir = EpubParser.dirName(opfPath);
    // manifest
    const manifest = new Map<string, ManifestItem>();
    const byHref = new Map<string, ManifestItem>();
    const itemRe = /<item\b[^>]*>/gi;
    let itemMatch = itemRe.exec(opf);
    while (itemMatch !== null) {
      const tag = itemMatch[0];
      const item = new ManifestItem();
      item.id = EpubParser.attrValue(tag, 'id');
      item.href = EpubParser.attrValue(tag, 'href');
      item.mediaType = EpubParser.attrValue(tag, 'media-type');
      item.properties = EpubParser.attrValue(tag, 'properties');
      if (item.id !== '' && item.href !== '') {
        manifest.set(item.id, item);
        byHref.set(EpubParser.joinPath(opfDir, item.href), item);
      }
      itemMatch = itemRe.exec(opf);
    }
    if (manifest.size === 0) {
      throw new Error('invalid_epub_manifest');
    }
    // spine
    const spineIds: string[] = [];
    const spineRe = /<itemref\b[^>]*>/gi;
    let spineMatch = spineRe.exec(opf);
    while (spineMatch !== null) {
      const idref = EpubParser.attrValue(spineMatch[0], 'idref');
      if (idref !== '') {
        spineIds.push(idref);
      }
      spineMatch = spineRe.exec(opf);
    }
    if (spineIds.length === 0) {
      // 无 spine：manifest 中全部 xhtml 按文档顺序兜底
      manifest.forEach((item: ManifestItem): void => {
        if (item.mediaType === 'application/xhtml+xml' || item.mediaType === 'text/html') {
          spineIds.push(item.id);
        }
      });
    }
    if (spineIds.length === 0) {
      throw new Error('invalid_epub_spine');
    }
    const result = new EpubBookResult();
    // metadata
    result.title = EpubParser.firstTagContent(opf, 'dc:title');
    result.author = EpubParser.firstTagContent(opf, 'dc:creator');
    // 目录名（ncx / nav），按 href 索引
    const namesByHref = EpubParser.parseTocNames(opf, opfDir, manifest);
    // 章节读取 + 引用重写
    for (const id of spineIds) {
      const item = manifest.get(id);
      if (item === undefined) {
        continue;
      }
      const absPath = EpubParser.joinPath(opfDir, item.href);
      const raw = BookFileIo.readBytes(absPath);
      if (raw === null) {
        continue;
      }
      const html = BookTextCodec.decodeXml(raw);
      const chapterDir = EpubParser.dirName(absPath);
      const rewritten = EpubParser.rewriteRefs(html, chapterDir);
      result.chapters.push(rewritten);
      const hrefKey = absPath;
      const tocName = namesByHref.get(hrefKey);
      if (tocName !== undefined && tocName !== '') {
        result.chapterNames.push(tocName);
      } else {
        const titleName = EpubParser.extractTitle(rewritten);
        result.chapterNames.push(titleName !== '' ? titleName : `${result.chapters.length}`);
      }
    }
    if (result.chapters.length === 0) {
      throw new Error('empty_book');
    }
    // 封面
    result.coverPath = EpubParser.resolveCover(opf, opfDir, manifest, byHref);
    return result;
  }

  // ---------------- 内部实现 ----------------

  // 取标签属性值
  private static attrValue(tag: string, name: string): string {
    const re = new RegExp(`\\b${name}\\s*=\\s*["']([^"']*)["']`, 'i');
    const m = re.exec(tag);
    return m !== null ? m[1] : '';
  }

  // 段落路径拼接 + '.'/'..' 归一化 + 百分号解码
  private static joinPath(baseDir: string, rel: string): string {
    let decoded = rel;
    try {
      decoded = decodeURIComponent(rel);
    } catch (e) {
      decoded = rel;
    }
    const combined = decoded.startsWith('/') ? decoded : `${baseDir}/${decoded}`;
    const parts = combined.split('/');
    const stack: string[] = [];
    for (const part of parts) {
      if (part === '' || part === '.') {
        continue;
      }
      if (part === '..') {
        if (stack.length > 0) {
          stack.pop();
        }
        continue;
      }
      stack.push(part);
    }
    return stack.join('/');
  }

  private static dirName(path: string): string {
    const idx = path.lastIndexOf('/');
    return idx > 0 ? path.substring(0, idx) : path;
  }

  private static firstTagContent(xml: string, tag: string): string {
    const re = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)</${tag}>`, 'i');
    const m = re.exec(xml);
    if (m === null) {
      return '';
    }
    return EpubParser.cleanText(m[1]);
  }

  private static cleanText(raw: string): string {
    let text = raw.replace(/<[^>]+>/g, ' ');
    text = text.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"').replace(/&#39;/g, '\'').replace(/&nbsp;/g, ' ');
    return text.replace(/\s+/g, ' ').trim();
  }

  // ncx（EPUB2）/ nav（EPUB3）目录：href（绝对化）→ 章节名
  private static parseTocNames(opf: string, opfDir: string, manifest: Map<string, ManifestItem>): Map<string, string> {
    const names = new Map<string, string>();
    // toc 属性 / spine toc 指向 ncx
    let ncxPath = '';
    const tocId = EpubParser.attrValue(EpubParser.findSpineTag(opf), 'toc');
    if (tocId !== '') {
      const item = manifest.get(tocId);
      if (item !== undefined) {
        ncxPath = EpubParser.joinPath(opfDir, item.href);
      }
    }
    if (ncxPath === '') {
      manifest.forEach((item: ManifestItem): void => {
        if (item.mediaType === 'application/x-dtbncx+xml' && ncxPath === '') {
          ncxPath = EpubParser.joinPath(opfDir, item.href);
        }
      });
    }
    if (ncxPath !== '') {
      const ncx = BookFileIo.readText(ncxPath);
      if (ncx !== null) {
        EpubParser.parseNcx(ncx, EpubParser.dirName(ncxPath), names);
      }
    }
    // EPUB3 nav
    manifest.forEach((item: ManifestItem): void => {
      if (item.properties.indexOf('nav') >= 0) {
        const navPath = EpubParser.joinPath(opfDir, item.href);
        const nav = BookFileIo.readText(navPath);
        if (nav !== null) {
          EpubParser.parseNav(nav, EpubParser.dirName(navPath), names);
        }
      }
    });
    return names;
  }

  private static findSpineTag(opf: string): string {
    const m = /<spine\b[^>]*>/i.exec(opf);
    return m !== null ? m[0] : '';
  }

  // ncx：<navLabel><text>名</text></navLabel> ... <content src="href"/>
  private static parseNcx(ncx: string, ncxDir: string, names: Map<string, string>): void {
    const re = /<navLabel>\s*<text>([\s\S]*?)<\/text>[\s\S]*?<content[^>]+src\s*=\s*["']([^"']+)["']/gi;
    let m = re.exec(ncx);
    while (m !== null) {
      const name = EpubParser.cleanText(m[1]);
      const href = EpubParser.joinPath(ncxDir, m[2]);
      if (name !== '' && !names.has(href)) {
        names.set(href, name);
      }
      m = re.exec(ncx);
    }
  }

  // EPUB3 nav：epub:type="toc" 的 <nav> 内 <a href="...">名</a>
  private static parseNav(nav: string, navDir: string, names: Map<string, string>): void {
    let body = nav;
    const navMatch = /<nav[^>]*epub:type\s*=\s*["']toc["'][^>]*>([\s\S]*?)<\/nav>/i.exec(nav);
    if (navMatch !== null) {
      body = navMatch[1];
    }
    const re = /<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi;
    let m = re.exec(body);
    while (m !== null) {
      const name = EpubParser.cleanText(m[2]);
      const href = EpubParser.joinPath(navDir, m[1]);
      if (name !== '' && !names.has(href)) {
        names.set(href, name);
      }
      m = re.exec(body);
    }
  }

  // <img src> / <image xlink:href> 相对引用 → file:// 绝对路径
  private static rewriteRefs(html: string, chapterDir: string): string {
    let out = html.replace(
      /(<img\b[^>]*?src\s*=\s*)(["'])([^"']+)\2/gi,
      (match: string, prefix: string, quote: string, ref: string): string => {
        return prefix + quote + EpubParser.resolveRef(ref, chapterDir) + quote;
      });
    out = out.replace(
      /(<image\b[^>]*?(?:xlink:)?href\s*=\s*)(["'])([^"']+)\2/gi,
      (match: string, prefix: string, quote: string, ref: string): string => {
        return prefix + quote + EpubParser.resolveRef(ref, chapterDir) + quote;
      });
    return out;
  }

  private static resolveRef(ref: string, chapterDir: string): string {
    if (ref.startsWith('http:') || ref.startsWith('https:') || ref.startsWith('data:')
      || ref.startsWith('#') || ref.startsWith('file:')) {
      return ref;
    }
    const abs = EpubParser.joinPath(chapterDir, ref);
    if (BookFileIo.exists(abs)) {
      return `file://${abs}`;
    }
    return ref;
  }

  // 封面：meta name="cover" / manifest properties="cover-image" / guide reference type="cover"
  private static resolveCover(opf: string, opfDir: string, manifest: Map<string, ManifestItem>,
    byHref: Map<string, ManifestItem>): string {
    // 1. <meta name="cover" content="id"/>
    const metaRe = /<meta[^>]+name\s*=\s*["']cover["'][^>]*>/gi;
    let metaMatch = metaRe.exec(opf);
    while (metaMatch !== null) {
      const contentId = EpubParser.attrValue(metaMatch[0], 'content');
      const item = manifest.get(contentId);
      if (item !== undefined) {
        const path = EpubParser.joinPath(opfDir, item.href);
        if (EpubParser.isImageFile(path)) {
          return path;
        }
      }
      metaMatch = metaRe.exec(opf);
    }
    // 2. manifest properties="cover-image"
    let coverByProps = '';
    manifest.forEach((item: ManifestItem): void => {
      if (coverByProps === '' && item.properties.indexOf('cover-image') >= 0) {
        const path = EpubParser.joinPath(opfDir, item.href);
        if (EpubParser.isImageFile(path)) {
          coverByProps = path;
        }
      }
    });
    if (coverByProps !== '') {
      return coverByProps;
    }
    // 3. guide <reference type="cover" href="..."/>
    const guideRe = /<reference[^>]+type\s*=\s*["']cover["'][^>]*>/gi;
    let guideMatch = guideRe.exec(opf);
    while (guideMatch !== null) {
      const href = EpubParser.attrValue(guideMatch[0], 'href');
      if (href !== '') {
        const path = EpubParser.joinPath(opfDir, href);
        if (EpubParser.isImageFile(path)) {
          return path;
        }
        // guide 可能指向 xhtml 封面页：取其内首个图片
        const coverImg = EpubParser.firstImageInHtml(path);
        if (coverImg !== '') {
          return coverImg;
        }
      }
      guideMatch = guideRe.exec(opf);
    }
    // 4. 兜底：manifest 首个图片资源
    let fallback = '';
    manifest.forEach((item: ManifestItem): void => {
      if (fallback === '' && item.mediaType.indexOf('image/') === 0) {
        const path = EpubParser.joinPath(opfDir, item.href);
        if (EpubParser.isImageFile(path)) {
          fallback = path;
        }
      }
    });
    return fallback;
  }

  private static isImageFile(path: string): boolean {
    if (!BookFileIo.exists(path)) {
      return false;
    }
    const lower = path.toLowerCase();
    return lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png')
      || lower.endsWith('.gif') || lower.endsWith('.webp') || lower.endsWith('.bmp');
  }

  // xhtml 内首个 <img src> 的绝对路径
  private static firstImageInHtml(htmlPath: string): string {
    const raw = BookFileIo.readBytes(htmlPath);
    if (raw === null) {
      return '';
    }
    const html = BookTextCodec.decodeXml(raw);
    const m = /<img\b[^>]*?src\s*=\s*["']([^"']+)["']/i.exec(html);
    if (m === null) {
      return '';
    }
    const abs = EpubParser.joinPath(EpubParser.dirName(htmlPath), m[1]);
    if (EpubParser.isImageFile(abs)) {
      return abs;
    }
    return '';
  }

  private static extractTitle(html: string): string {
    const m = /<title[^>]*>([\s\S]*?)<\/title>/i.exec(html);
    if (m !== null) {
      const name = EpubParser.cleanText(m[1]);
      if (name !== '') {
        return name.length > 80 ? name.substring(0, 80) : name;
      }
    }
    return '';
  }
}
