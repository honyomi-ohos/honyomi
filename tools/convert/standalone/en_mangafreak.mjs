// en/mangafreak — standalone scraper via shared generic driver
import { makeScraper } from './_lib.mjs';

export const runtime = 'wp';

export const config = {
  popular: {
    url: '{base}/Genre/All/{page}',
    item: 'div.ranking_item',
    link: 'a',
    img: 'img',
    hasNext: 'a.next_p',
  },
  search: {
    url: '{base}/Find/{query}',
    item: 'div.manga_search_item, div.mangaka_search_item',
    link: 'h3 a, h5 a',
    hasNext: 0,
  },
  details: {
    title: 'div.manga_series_data h5',
    cover: 'div.manga_series_image img',
    author: 'div.manga_series_data > div:eq(3)',
    artist: 'div.manga_series_data > div:eq(4)',
    genre: 'div.series_sub_genre_list a',
    description: 'div.manga_series_description p',
    status: 'div.manga_series_data > div:eq(2)',
    statusMap: { 'on-going': 'ongoing', ongoing: 'ongoing', completed: 'completed' },
  },
  chapters: {
    item: 'div.manga_series_list tr:has(a)',
    name: 'td:eq(0)',
    url: 'a',
    date: 'td:eq(1)',
    dateFormat: 'yyyy/MM/dd',
    reverse: true,
  },
  pages: {
    img: 'img#gohere[src]',
  },
};

const engine = makeScraper(config, {
  warnings: ['mini_images thumbnail rewrite and letter chapter numbers approximated'],
});

export const extract = engine.extract;
export const generate = engine.generate;
