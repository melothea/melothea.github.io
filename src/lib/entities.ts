// エンティティのビュー層：関係の取得・MV表示名の導出・逐語名の供給（正本：MV_DATABASE.md）。
// 名義の言語別解決は names.ts（4段カスケード）が担い、ここは構造（どの関係が誰を指すか）を返す。

import {
  query,
  queryOne,
  type EntityRow,
  type EntityType,
  type MvCreditRow,
  type MvRow,
  type MvSongRow,
  type NameRow,
  type SongArtistRow,
  type SongCreditRow,
  type SongRow,
} from './db.ts';
import { renderPerson, type Lang, type Rendered } from './names.ts';

export function allEntities(): EntityRow[] {
  return query<EntityRow>('SELECT id, entity_type FROM entities ORDER BY id');
}

export function getEntity(id: number): EntityRow | undefined {
  return queryOne<EntityRow>('SELECT id, entity_type FROM entities WHERE id = ?', id);
}

export const getSong = (id: number) => queryOne<SongRow>('SELECT * FROM songs WHERE id = ?', id);
export const getMv = (id: number) => queryOne<MvRow>('SELECT * FROM mvs WHERE id = ?', id);

/** 逐語の primary 名義行（person/group/song）。MV は持たない（導出）。 */
export function primaryNameRow(entityId: number): NameRow | undefined {
  return queryOne<NameRow>(
    'SELECT * FROM names WHERE entity_id = ? AND is_primary = 1 AND locale = ? LIMIT 1',
    entityId,
    'ja',
  ) ?? queryOne<NameRow>('SELECT * FROM names WHERE entity_id = ? AND is_primary = 1 LIMIT 1', entityId);
}

/** MV の表示名は mv_songs 経由で楽曲名から導出（確定事項：MVに独立の固有名を持たせない）。
 *  複数楽曲（メドレー）なら position 順の逐語 title 行を返す。 */
export function mvTitleRows(mvId: number): NameRow[] {
  return query<NameRow>(
    `SELECT n.* FROM names n
       JOIN mv_songs ms ON ms.song_id = n.entity_id
      WHERE ms.mv_id = ? AND n.is_primary = 1 AND n.name_type = 'title'
      ORDER BY ms.position, ms.id`,
    mvId,
  );
}

/** 一覧・リンク用の逐語名（言語中立）。text と lang を返す。 */
export function neutralName(entityId: number, entityType: EntityType): { text: string; lang: string } {
  if (entityType === 'mv') {
    const rows = mvTitleRows(entityId);
    if (rows.length) return { text: rows.map((r) => r.name_text).join(' / '), lang: rows[0]!.lang };
    return { text: `melothea${entityId}`, lang: 'mul' };
  }
  const p = primaryNameRow(entityId);
  return p ? { text: p.name_text, lang: p.lang } : { text: `melothea${entityId}`, lang: 'mul' };
}

/** MV の日付（当時名義導出の atDate）。production_year を ISO 部分日付として使う。 */
export function mvDate(mv: MvRow): string | null {
  return mv.production_year != null ? String(mv.production_year) : null;
}

// ---- 関係の取得 ----

// MV ページ：収録楽曲・クレジット
export const mvSongs = (mvId: number) =>
  query<MvSongRow>('SELECT * FROM mv_songs WHERE mv_id = ? ORDER BY position, id', mvId);
export const mvCredits = (mvId: number) =>
  query<MvCreditRow>('SELECT * FROM mv_credits WHERE mv_id = ? ORDER BY id', mvId);

// 楽曲ページ：アーティスト・作家クレジット・収録映像
export const songArtists = (songId: number) =>
  query<SongArtistRow>('SELECT * FROM song_artists WHERE song_id = ? ORDER BY id', songId);
export const songCredits = (songId: number) =>
  query<SongCreditRow>('SELECT * FROM song_credits WHERE song_id = ? ORDER BY id', songId);
export const mvsOfSong = (songId: number) =>
  query<MvSongRow>('SELECT * FROM mv_songs WHERE song_id = ? ORDER BY id', songId);

// 人物・グループページ：関与の逆引き
export const mvCreditsOfEntity = (entityId: number) =>
  query<MvCreditRow>('SELECT * FROM mv_credits WHERE entity_id = ? ORDER BY mv_id, id', entityId);
export const songCreditsOfEntity = (entityId: number) =>
  query<SongCreditRow>('SELECT * FROM song_credits WHERE entity_id = ? ORDER BY song_id, id', entityId);
export const songArtistOf = (entityId: number) =>
  query<SongArtistRow>('SELECT * FROM song_artists WHERE entity_id = ? ORDER BY song_id, id', entityId);

/** entity_type を引く小補助（リンク先の種別ラベル用）。 */
export function entityTypeOf(id: number): EntityType | undefined {
  return getEntity(id)?.entity_type;
}

/** MV に統合表示する楽曲クレジット（作詞・作曲・編曲）を mv_songs 経由で収録楽曲ごとに束ねる。
 *  単曲MVは1グループ（クレジット欄に統合）、複数楽曲（メドレー）は楽曲ごとに小見出しで分ける。 */
export function mvSongCreditGroups(mvId: number): { songId: number; credits: SongCreditRow[] }[] {
  return mvSongs(mvId).map((ms) => ({ songId: ms.song_id, credits: songCredits(ms.song_id) }));
}

/** MV のアーティスト：mv_songs 経由の収録楽曲の song_artists role='main' を重複なし導出。
 *  メドレー（複数楽曲）は position 順に走査し entity_id で重複除去。featured は含めない
 *  （実例投入時に条件付き表示を実装予定）。 */
export function mvMainArtists(mvId: number): SongArtistRow[] {
  const rows = query<SongArtistRow>(
    `SELECT sa.* FROM song_artists sa
       JOIN mv_songs ms ON ms.song_id = sa.song_id
      WHERE ms.mv_id = ? AND sa.role = 'main'
      ORDER BY ms.position, ms.id, sa.id`,
    mvId,
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

/** アーティストとして紐づく MV の逆引き：song_artists role='main' → mv_songs を JOIN し、
 *  当該エンティティが main アーティストの MV を mv_id で重複除去。source は帰属を担う
 *  song_artists 行のもの。featured は含めない。 */
export function artistMvsOf(entityId: number): { mvId: number; source: string }[] {
  const rows = query<{ mv_id: number; source: string }>(
    `SELECT ms.mv_id AS mv_id, sa.source AS source
       FROM song_artists sa
       JOIN mv_songs ms ON ms.song_id = sa.song_id
      WHERE sa.entity_id = ? AND sa.role = 'main'
      ORDER BY ms.mv_id, ms.id`,
    entityId,
  );
  const seen = new Set<number>();
  const out: { mvId: number; source: string }[] = [];
  for (const r of rows) {
    if (!seen.has(r.mv_id)) {
      seen.add(r.mv_id);
      out.push({ mvId: r.mv_id, source: r.source });
    }
  }
  return out;
}

/** 人物・グループの楽曲関与を楽曲ごとに集約：song_artists role='main'（アーティスト）と
 *  song_credits 全roleを song_id でグループ化。featured は含めない。各楽曲の役割エントリを
 *  Artist系→作詞→作曲→編曲→プロデュース の規定順に整列し、楽曲は song_id 昇順で返す。 */
export function entitySongRoles(
  entityId: number,
): { songId: number; roles: { roleKey: string; source: string }[] }[] {
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
  const bySong = new Map<number, { roleKey: string; source: string }[]>();
  const add = (songId: number, roleKey: string, source: string) => {
    const list = bySong.get(songId) ?? [];
    list.push({ roleKey, source });
    bySong.set(songId, list);
  };
  for (const r of artist) add(r.song_id, r.role, r.source);
  for (const r of credits) add(r.song_id, r.role, r.source);
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
  joined: string | null;
  left: string | null;
  ended: number;
  source: string;
};

/** 1区間の期間文字列。to=NULL は開区間（ended=0）のみ「YYYY–」。to=NULL かつ ended=1 は
 *  描画未定義のため停止（共通規則）。 */
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
  periods: { text: string; source: string }[]; // joined 昇順
}

/** memberships 行を「相手」で集約。並び：集約後の最古 joined 昇順、タイは entitySortKey の
 *  コードポイント。各グループ内の期間は joined 昇順。 */
function aggregateMemberships(rows: MembershipRow[], otherOf: (r: MembershipRow) => number): PeriodGroup[] {
  const byOther = new Map<number, MembershipRow[]>();
  for (const r of rows) {
    const k = otherOf(r);
    const list = byOther.get(k);
    if (list) list.push(r);
    else byOther.set(k, [r]);
  }
  const groups = [...byOther.entries()].map(([entityId, rs]) => {
    const sorted = rs.slice().sort((a, b) => cmpStr(a.joined ?? '', b.joined ?? ''));
    return {
      entityId,
      earliest: sorted[0]?.joined ?? '',
      sortKey: entitySortKey(entityId),
      periods: sorted.map((r) => ({ text: periodText(r.joined, r.left, r.ended), source: r.source })),
    };
  });
  groups.sort((a, b) => cmpStr(a.earliest, b.earliest) || cmpStr(a.sortKey, b.sortKey));
  return groups.map(({ entityId, periods }) => ({ entityId, periods }));
}

/** グループのメンバー（memberships を member_id で集約）。 */
export function groupMembers(groupId: number): PeriodGroup[] {
  const rows = query<MembershipRow>(
    'SELECT id, group_id, member_id, joined, "left", ended, source FROM memberships WHERE group_id = ? ORDER BY member_id, joined, id',
    groupId,
  );
  return aggregateMemberships(rows, (r) => r.member_id);
}

/** エンティティの所属（memberships を member_id=当該で逆引き、group_id で集約）。 */
export function entityMemberships(entityId: number): PeriodGroup[] {
  const rows = query<MembershipRow>(
    'SELECT id, group_id, member_id, joined, "left", ended, source FROM memberships WHERE member_id = ? ORDER BY group_id, joined, id',
    entityId,
  );
  return aggregateMemberships(rows, (r) => r.group_id);
}

/** グループの活動期間（group_activity_periods を active_from 昇順）。 */
export function groupActivityPeriods(groupId: number): { text: string; source: string }[] {
  const rows = query<{ active_from: string | null; active_to: string | null; ended: number; source: string }>(
    'SELECT active_from, active_to, ended, source FROM group_activity_periods WHERE group_id = ? ORDER BY active_from, id',
    groupId,
  );
  return rows.map((r) => ({ text: periodText(r.active_from, r.active_to, r.ended), source: r.source }));
}

/** role='director' の mv_credits を持つエンティティの重複なし導出（属性は保存しない・ビルド時クエリ）。 */
export function directorEntities(): EntityRow[] {
  return query<EntityRow>(
    `SELECT DISTINCT e.id, e.entity_type
       FROM entities e JOIN mv_credits mc ON mc.entity_id = e.id
      WHERE mc.role = 'director'
      ORDER BY e.id`,
  );
}

/** 見出し・リンクの表示名を人物文脈（renderPerson）で解決する。ただし MV は names 行を持たない
 *  ため、mv_songs 経由で収録楽曲の renderPerson からタイトルを導出する（複数楽曲は ' / ' 結合、
 *  導出不能時のみ識別子 melothea{n} に劣化）。見出しと entity 文脈のリンク解決で共用する。 */
export function renderDisplayName(entityId: number, entityType: EntityType, lang: Lang): Rendered {
  if (entityType === 'mv') {
    const parts = mvSongs(entityId).map((r) => renderPerson(r.song_id, lang));
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
