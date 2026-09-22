// ja/manga1000 — WordPress-style scraper via shared generic driver
import { makeScraper } from './_lib.mjs';

export const runtime = 'wp';

export const config = {
  popular: {
    firstUrl: '{base}',
    url: '{base}/page/{page}/',
    item: 'article.post.manga',
    link: '.entry-title a',
    img: '.featured-thumb img',
    hasNext: 'nav.pagination a.next',
  },
  search: {
    firstUrl: '{base}/search?query={query}',
    url: '{base}/search/page/{page}?query={query}',
    item: 'article.post.manga',
    link: '.entry-title a',
    hasNext: 'nav.pagination a.next',
  },
  details: {
    title: 'h1.entry-title',
    cover: '.entry-content img',
    author: '.entry-content > p:contains(Author:)',
    genre: '.entry-content > p:contains(Category:) a',
    description: '.entry-content > p',
  },
  chapters: {
    item: '.chaplist table tbody tr td',
    url: 'a',
  },
  pages: {
    img: '.entry-content img',
  },
  headers: { Referer: '{base}/' },
};

const engine = makeScraper(config, {
  warnings: [
    'author text keeps "Author:" prefix; description may include author/category lines',
    'lazy.png placeholder pages not filtered (data-src preferred)',
  ],
});

export const extract = engine.extract;
export const generate = engine.generate;
