// エンティティのビュー層：関係の取得・MV表示名の導出・逐語名の供給。
// 名義の言語別解決は names.ts（4段カスケード）が担い、ここは構造（どの関係が誰を指すか）を返す。

import {
  query,
  queryOne,
  type EntityRow,
  type EntityType,
  type VideoCreditRow,
  type VideoRow,
  type VideoSongRow,
  type NameRow,
  type SongArtistRow,
  type SongCreditRow,
  type SongRow,
} from './db.ts';
import { renderPerson, type Lang, type Rendered } from './names.ts';

// ---- 出典（各親表の {親表名}_sources 子テーブル。1ソース1行）----

export interface SourceEntry {
  label: string;
  descriptor: string | null;
  url: string | null;
  referencedAt: string | null;
  recordRef: string | null;
}

/** 親行に紐づく出典行を投入順（id 昇順）で返す。childTable は内部固定の表名のみ。 */
type SourceChildTable =
  | 'names_sources'
  | 'memberships_sources'
  | 'group_activity_periods_sources'
  | 'song_artists_sources'
  | 'song_credits_sources'
  | 'video_credits_sources';

export function sourcesFor(childTable: SourceChildTable, parentId: number): SourceEntry[] {
  const rows = query<{
    label: string;
    descriptor: string | null;
    url: string | null;
    referenced_at: string | null;
    record_ref: string | null;
  }>(
    `SELECT label, descriptor, url, referenced_at, record_ref FROM ${childTable} WHERE parent_id = ? ORDER BY id`,
    parentId,
  );
  return rows.map((r) => ({
    label: r.label,
    descriptor: r.descriptor,
    url: r.url,
    referencedAt: r.referenced_at,
    recordRef: r.record_ref,
  }));
}

export function allEntities(): EntityRow[] {
  return query<EntityRow>('SELECT id, entity_type FROM entities ORDER BY id');
}

export function getEntity(id: number): EntityRow | undefined {
  return queryOne<EntityRow>('SELECT id, entity_type FROM entities WHERE id = ?', id);
}

export const getSong = (id: number) => queryOne<SongRow>('SELECT * FROM songs WHERE id = ?', id);
export const getVideo = (id: number) => queryOne<VideoRow>('SELECT * FROM videos WHERE id = ?', id);

/** 逐語の primary 名義行（person/group/song）。MV は持たない（導出）。 */
export function primaryNameRow(entityId: number): NameRow | undefined {
  return queryOne<NameRow>(
    'SELECT * FROM names WHERE entity_id = ? AND is_primary = 1 AND locale = ? LIMIT 1',
    entityId,
    'ja',
  ) ?? queryOne<NameRow>('SELECT * FROM names WHERE entity_id = ? AND is_primary = 1 LIMIT 1', entityId);
}

/** 楽曲1件の中立表示名行：ja primary title → 任意の primary title → 先頭の title 行（id昇順）。 */
function songTitleRow(songId: number): NameRow | undefined {
  return (
    queryOne<NameRow>(
      "SELECT * FROM names WHERE entity_id = ? AND is_primary = 1 AND name_type = 'title' AND locale = 'ja' LIMIT 1",
      songId,
    ) ??
    queryOne<NameRow>(
      "SELECT * FROM names WHERE entity_id = ? AND is_primary = 1 AND name_type = 'title' LIMIT 1",
      songId,
    ) ??
    queryOne<NameRow>(
      "SELECT * FROM names WHERE entity_id = ? AND name_type = 'title' ORDER BY id LIMIT 1",
      songId,
    )
  );
}

/** MV の表示名は video_songs 経由で楽曲名から導出。
 *  複数楽曲（メドレー）なら position 順に、楽曲ごとに1行（songTitleRow）を返す。 */
export function videoTitleRows(videoId: number): NameRow[] {
  return videoSongs(videoId)
    .map((ms) => songTitleRow(ms.song_id))
    .filter((r): r is NameRow => r != null);
}

/** 一覧・リンク用の逐語名（言語中立）。text と lang を返す。 */
export function neutralName(entityId: number, entityType: EntityType): { text: string; lang: string } {
  if (entityType === 'video') {
    const rows = videoTitleRows(entityId);
    if (rows.length) return { text: rows.map((r) => r.name_text).join(' / '), lang: rows[0]!.lang };
    return { text: `melothea${entityId}`, lang: 'mul' };
  }
  const p = primaryNameRow(entityId);
  return p ? { text: p.name_text, lang: p.lang } : { text: `melothea${entityId}`, lang: 'mul' };
}

/** 楽曲の年：song_release_dates の当該 song_id の行集合から最古 date を選び、年（先頭4桁）を返す。
 *  行ゼロなら年なし（null）。 */
export function songYear(songId: number): string | null {
  const row = queryOne<{ date: string }>(
    'SELECT date FROM song_release_dates WHERE song_id = ? ORDER BY date, id LIMIT 1',
    songId,
  );
  return row ? row.date.slice(0, 4) : null;
}

/** MV の年：video_release_dates の当該 video_id に行があれば最古行の年。無ければ video_songs が
 *  単曲（1行）のときのみ紐づく楽曲の年（songYear）へフォールバック。複数楽曲（メドレー）は
 *  フォールバックせず年なし。いずれも得られなければ null。
 *  当時名義導出の atDate（ISO 部分日付＝年文字列）としても用いる。 */
export function videoYear(videoId: number): string | null {
  const row = queryOne<{ date: string }>(
    'SELECT date FROM video_release_dates WHERE video_id = ? ORDER BY date, id LIMIT 1',
    videoId,
  );
  if (row) return row.date.slice(0, 4);
  const songs = videoSongs(videoId);
  return songs.length === 1 ? songYear(songs[0]!.song_id) : null;
}

// ---- 関係の取得 ----

// MV ページ：収録楽曲・クレジット
export const videoSongs = (videoId: number) =>
  query<VideoSongRow>('SELECT * FROM video_songs WHERE video_id = ? ORDER BY position, id', videoId);
export const videoCredits = (videoId: number) =>
  query<VideoCreditRow>('SELECT * FROM video_credits WHERE video_id = ? ORDER BY id', videoId);

// 楽曲ページ：アーティスト・作家クレジット・収録映像
export const songArtists = (songId: number) =>
  query<SongArtistRow>('SELECT * FROM song_artists WHERE song_id = ? ORDER BY id', songId);
export const songCredits = (songId: number) =>
  query<SongCreditRow>('SELECT * FROM song_credits WHERE song_id = ? ORDER BY id', songId);
export const videosOfSong = (songId: number) =>
  query<VideoSongRow>('SELECT * FROM video_songs WHERE song_id = ? ORDER BY id', songId);

// 人物・グループページ：関与の逆引き
export const videoCreditsOfEntity = (entityId: number) =>
  query<VideoCreditRow>('SELECT * FROM video_credits WHERE entity_id = ? ORDER BY video_id, id', entityId);
export const songCreditsOfEntity = (entityId: number) =>
  query<SongCreditRow>('SELECT * FROM song_credits WHERE entity_id = ? ORDER BY song_id, id', entityId);
export const songArtistOf = (entityId: number) =>
  query<SongArtistRow>('SELECT * FROM song_artists WHERE entity_id = ? ORDER BY song_id, id', entityId);

/** entity_type を引く小補助（リンク先の種別ラベル用）。 */
export function entityTypeOf(id: number): EntityType | undefined {
  return getEntity(id)?.entity_type;
}

/** MV に統合表示する楽曲クレジット（作詞・作曲・編曲）を video_songs 経由で収録楽曲ごとに束ねる。
 *  単曲MVは1グループ（クレジット欄に統合）、複数楽曲（メドレー）は楽曲ごとに小見出しで分ける。 */
export function videoSongCreditGroups(videoId: number): { songId: number; credits: SongCreditRow[] }[] {
  return videoSongs(videoId).map((ms) => ({ songId: ms.song_id, credits: songCredits(ms.song_id) }));
}

/** MV のアーティスト：video_songs 経由の収録楽曲の song_artists role='main' を重複なし導出。
 *  メドレー（複数楽曲）は position 順に走査し entity_id で重複除去。featured は含めない。 */
export function videoMainArtists(videoId: number): SongArtistRow[] {
  const rows = query<SongArtistRow>(
    `SELECT sa.* FROM song_artists sa
       JOIN video_songs ms ON ms.song_id = sa.song_id
      WHERE ms.video_id = ? AND sa.role = 'main'
      ORDER BY ms.position, ms.id, sa.id`,
    videoId,
  );
  const seen = new Set<number>();
  const out: SongArtistRow[] = [];
  for (const r of rows) {
    if (!seen.has(r.entity_id)) {
      seen.add(r.entity_id);
      out.push(r);
    }
  }
  return out;
}

/** アーティストとして紐づく MV の逆引き：song_artists role='main' → video_songs を JOIN し、
 *  当該エンティティが main アーティストの MV を video_id で重複除去。出典は帰属を担う
 *  song_artists 行の子テーブル（song_artists_sources）から採る。featured は含めない。 */
export function artistVideosOf(entityId: number): { videoId: number; sources: SourceEntry[] }[] {
  const rows = query<{ video_id: number; sa_id: number }>(
    `SELECT ms.video_id AS video_id, sa.id AS sa_id
       FROM song_artists sa
       JOIN video_songs ms ON ms.song_id = sa.song_id
      WHERE sa.entity_id = ? AND sa.role = 'main'
      ORDER BY ms.video_id, ms.id`,
    entityId,
  );
  const seen = new Set<number>();
  const out: { videoId: number; sources: SourceEntry[] }[] = [];
  for (const r of rows) {
    if (!seen.has(r.video_id)) {
      seen.add(r.video_id);
      out.push({ videoId: r.video_id, sources: sourcesFor('song_artists_sources', r.sa_id) });
    }
  }
  return out;
}

/** 人物・グループの楽曲関与を楽曲ごとに集約：song_artists role='main'（アーティスト）と
 *  song_credits 全roleを song_id でグループ化。featured は含めない。各楽曲の役割エントリを
 *  Artist系→作詞→作曲→編曲→プロデュース の規定順に整列し、楽曲は song_id 昇順で返す。 */
export function entitySongRoles(
  entityId: number,
): { songId: number; roles: { roleKey: string; sources: SourceEntry[] }[] }[] {
  const artist = query<SongArtistRow>(
    "SELECT * FROM song_artists WHERE entity_id = ? AND role = 'main' ORDER BY song_id, id",
    entityId,
  );
  const credits = query<SongCreditRow>(
    'SELECT * FROM song_credits WHERE entity_id = ? ORDER BY song_id, id',
    entityId,
  );
  const roleOrder = ['main', 'lyricist', 'composer', 'arranger', 'producer'];
  const rank = (k: string) => {
    const i = roleOrder.indexOf(k);
    return i < 0 ? roleOrder.length : i;
  };
  const bySong = new Map<number, { roleKey: string; sources: SourceEntry[] }[]>();
  const add = (songId: number, roleKey: string, sources: SourceEntry[]) => {
    const list = bySong.get(songId) ?? [];
    list.push({ roleKey, sources });
    bySong.set(songId, list);
  };
  for (const r of artist) add(r.song_id, r.role, sourcesFor('song_artists_sources', r.id));
  for (const r of credits) add(r.song_id, r.role, sourcesFor('song_credits_sources', r.id));
  return [...bySong.keys()]
    .sort((a, b) => a - b)
    .map((songId) => ({
      songId,
      roles: bySong.get(songId)!.slice().sort((x, y) => rank(x.roleKey) - rank(y.roleKey)),
    }));
}

// ---- memberships / 活動期間の集約（グループのメンバー節・エンティティの所属節・活動期間facts）----

const EN_DASH = '–';
type MembershipRow = {
  id: number;
  group_id: number;
  member_id: number;
  membership_from: string | null;
  membership_to: string | null;
  ended: number;
};

/** 1区間の期間文字列。to=NULL は開区間（ended=0）のみ「YYYY–」。to=NULL かつ ended=1 は
 *  描画未定義のため停止。 */
function periodText(from: string | null, to: string | null, ended: number): string {
  if (to == null && ended === 1) {
    throw new Error(`period undefined (from=${from}, to=NULL, ended=1): 描画未定義。共通規則により停止`);
  }
  return `${from ?? ''}${EN_DASH}${to ?? ''}`;
}

/** 並び用ソートキー：en primary の name_text、不在なら ja primary の name_text（素のコードポイント比較）。 */
function entitySortKey(entityId: number): string {
  const en = queryOne<{ name_text: string }>(
    "SELECT name_text FROM names WHERE entity_id = ? AND locale = 'en' AND is_primary = 1 LIMIT 1",
    entityId,
  );
  if (en) return en.name_text;
  const ja = queryOne<{ name_text: string }>(
    "SELECT name_text FROM names WHERE entity_id = ? AND locale = 'ja' AND is_primary = 1 LIMIT 1",
    entityId,
  );
  return ja?.name_text ?? '';
}

const cmpStr = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);

export interface PeriodGroup {
  entityId: number; // 相手（member_id または group_id）
  periods: { text: string; sources: SourceEntry[] }[]; // membership_from 昇順
}

/** memberships 行を「相手」で集約。並び：集約後の最古 membership_from 昇順、タイは entitySortKey の
 *  コードポイント。各グループ内の期間は membership_from 昇順。 */
function aggregateMemberships(rows: MembershipRow[], otherOf: (r: MembershipRow) => number): PeriodGroup[] {
  const byOther = new Map<number, MembershipRow[]>();
  for (const r of rows) {
    const k = otherOf(r);
    const list = byOther.get(k);
    if (list) list.push(r);
    else byOther.set(k, [r]);
  }
  const groups = [...byOther.entries()].map(([entityId, rs]) => {
    const sorted = rs.slice().sort((a, b) => cmpStr(a.membership_from ?? '', b.membership_from ?? ''));
    return {
      entityId,
      earliest: sorted[0]?.membership_from ?? '',
      sortKey: entitySortKey(entityId),
      periods: sorted.map((r) => ({
        text: periodText(r.membership_from, r.membership_to, r.ended),
        sources: sourcesFor('memberships_sources', r.id),
      })),
    };
  });
  groups.sort((a, b) => cmpStr(a.earliest, b.earliest) || cmpStr(a.sortKey, b.sortKey));
  return groups.map(({ entityId, periods }) => ({ entityId, periods }));
}

/** グループのメンバー（memberships を member_id で集約）。 */
export function groupMembers(groupId: number): PeriodGroup[] {
  const rows = query<MembershipRow>(
    'SELECT id, group_id, member_id, membership_from, membership_to, ended FROM memberships WHERE group_id = ? ORDER BY member_id, membership_from, id',
    groupId,
  );
  return aggregateMemberships(rows, (r) => r.member_id);
}

/** エンティティの所属（memberships を member_id=当該で逆引き、group_id で集約）。 */
export function entityMemberships(entityId: number): PeriodGroup[] {
  const rows = query<MembershipRow>(
    'SELECT id, group_id, member_id, membership_from, membership_to, ended FROM memberships WHERE member_id = ? ORDER BY group_id, membership_from, id',
    entityId,
  );
  return aggregateMemberships(rows, (r) => r.group_id);
}

/** グループの活動期間（group_activity_periods を active_from 昇順）。 */
export function groupActivityPeriods(groupId: number): { text: string; sources: SourceEntry[] }[] {
  const rows = query<{ id: number; active_from: string | null; active_to: string | null; ended: number }>(
    'SELECT id, active_from, active_to, ended FROM group_activity_periods WHERE group_id = ? ORDER BY active_from, id',
    groupId,
  );
  return rows.map((r) => ({
    text: periodText(r.active_from, r.active_to, r.ended),
    sources: sourcesFor('group_activity_periods_sources', r.id),
  }));
}

/** role='director' の video_credits を持つエンティティの重複なし導出（属性は保存しない・ビルド時クエリ）。 */
export function directorEntities(): EntityRow[] {
  return query<EntityRow>(
    `SELECT DISTINCT e.id, e.entity_type
       FROM entities e JOIN video_credits mc ON mc.entity_id = e.id
      WHERE mc.role = 'director'
      ORDER BY e.id`,
  );
}

/** 見出し・リンクの表示名を人物文脈（renderPerson）で解決する。ただし MV は names 行を持たない
 *  ため、video_songs 経由で収録楽曲の renderPerson からタイトルを導出する（複数楽曲は ' / ' 結合、
 *  導出不能時のみ識別子 melothea{n} に劣化）。見出しと entity 文脈のリンク解決で共用する。 */
export function renderDisplayName(entityId: number, entityType: EntityType, lang: Lang): Rendered {
  if (entityType === 'video') {
    const parts = videoSongs(entityId).map((r) => renderPerson(r.song_id, lang));
    if (parts.length === 0) {
      return { main: { text: `melothea${entityId}`, lang: 'mul' }, degraded: true, linkId: entityId };
    }
    const first = parts[0]!;
    return {
      main: { text: parts.map((p) => p.main.text).join(' / '), lang: first.main.lang },
      degraded: parts.every((p) => p.degraded),
      linkId: entityId,
    };
  }
  return renderPerson(entityId, lang);
}
