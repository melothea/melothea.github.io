// 表示ラベルとURL補助。
// ラベルはUIのchrome（言語依存）。エンティティ／役割の語彙キー自体は言語中立の識別子であり、
// 言語中立ハブではキーと逐語名をそのまま出す（下の label は言語ページ専用）。

import type { EntityType } from './db.ts';

export const LOCALES = ['ja', 'en'] as const;
export type Lang = (typeof LOCALES)[number];

export const isLang = (v: string): v is Lang => (LOCALES as readonly string[]).includes(v);

// URL（trailingSlash:'always'・build.format:'directory' と一致。全経路で末尾スラッシュ）
export const neutralPath = (id: number) => `/melothea${id}/`;
export const langPath = (lang: Lang, id: number) => `/${lang}/melothea${id}/`;
export const langHome = (lang: Lang) => `/${lang}/`;
export const neutralHome = () => `/`;

// 言語中立ハブの二言語併記ラベル
export const bi = (ja: string, en: string) => `${ja} / ${en}`;

export const SITE_NAME = 'Melothea';

// 役割語彙 → 表示ラベル（言語ページ）
export const roleLabel: Record<Lang, Record<string, string>> = {
  ja: {
    director: '監督',
    appearance: '出演',
    choreographer: '振付',
    cinematographer: '撮影',
    lyricist: '作詞',
    composer: '作曲',
    arranger: '編曲',
    producer: 'プロデュース',
    main: 'アーティスト',
    featured: '客演',
  },
  en: {
    director: 'Director',
    appearance: 'Appearance',
    choreographer: 'Choreographer',
    cinematographer: 'Cinematographer',
    lyricist: 'Lyrics',
    composer: 'Music',
    arranger: 'Arrangement',
    producer: 'Producer',
    main: 'Artist',
    featured: 'Featured',
  },
};

export const typeLabel: Record<Lang, Record<EntityType, string>> = {
  ja: { person: '人物', group: 'グループ', song: '楽曲', video: '映像（MV）' },
  en: { person: 'Person', group: 'Group', song: 'Song', video: 'Music video' },
};

// 言語中立ハブの言語選択行用：種別短縮ラベル（ja のみ。en は typeLabel.en を用いる）
export const neutralTypeLabelJa: Record<EntityType, string> = {
  video: 'MV',
  song: '曲',
  person: '人物',
  group: 'グループ',
};

export const videoTypeLabel: Record<Lang, Record<string, string>> = {
  ja: { music_video: 'ミュージックビデオ' },
  en: { music_video: 'Music video' },
};

// リリース種別語彙 → 表示ラベル（言語ページ）。統制語彙リストは現在空のため写像も空。
export const releaseTypeLabel: Record<Lang, Record<string, string>> = {
  ja: {},
  en: {},
};

// 出典ラベル語彙（source_labels）→ 表示語（言語ページ）
export const sourceLabel: Record<Lang, Record<string, string>> = {
  ja: {
    disc: '音楽ディスク',
    video_disc: '映像ディスク',
    video_stream: '映像ストリーミング',
    apple_music: 'Apple Music',
    youtube_music: 'YouTube Music',
    official_site: '公式サイト',
    official_sns: '公式SNS',
    web_news: 'Webニュース',
    editor_verified: '編纂者確認',
  },
  en: {
    disc: 'Music disc',
    video_disc: 'Video disc',
    video_stream: 'Video streaming',
    apple_music: 'Apple Music',
    youtube_music: 'YouTube Music',
    official_site: 'Official site',
    official_sns: 'Official SNS',
    web_news: 'Web news',
    editor_verified: 'Editor verified',
  },
};

// セクション見出し等（言語ページ）
export const ui: Record<Lang, Record<string, string>> = {
  ja: {
    release: 'リリース',
    productionYear: '制作年',
    videoType: '種別',
    songs: '楽曲',
    musicVideos: '映像（MV）',
    credits: 'クレジット',
    artists: 'アーティスト',
    appearsIn: '収録された映像',
    songCredits: '楽曲クレジット',
    videoWork: '映像での関与',
    asArtist: 'アーティストとして',
    activePeriod: '活動期間',
    members: 'メンバー',
    membership: '所属',
    otherLanguages: '他の言語で見る',
    neutralPage: '言語中立ページ',
    id: 'ID',
    kind: '種別区分',
    source: '出典',
    sources: '出典',
    home: '一覧',
    langName: '日本語',
    watchOnYoutube: 'YouTubeで見る',
    play: '再生',
  },
  en: {
    release: 'Release',
    productionYear: 'Production year',
    videoType: 'Type',
    songs: 'Songs',
    musicVideos: 'Music videos',
    credits: 'Credits',
    artists: 'Artists',
    appearsIn: 'Featured in',
    songCredits: 'Song credits',
    videoWork: 'Music video work',
    asArtist: 'As artist',
    activePeriod: 'Active',
    members: 'Members',
    membership: 'Membership',
    otherLanguages: 'View in other languages',
    neutralPage: 'Language-neutral page',
    id: 'ID',
    kind: 'Type',
    source: 'Source',
    sources: 'Sources',
    home: 'Index',
    langName: 'English',
    watchOnYoutube: 'Watch on YouTube',
    play: 'Play',
  },
};

export const otherLang = (lang: Lang): Lang => (lang === 'ja' ? 'en' : 'ja');
