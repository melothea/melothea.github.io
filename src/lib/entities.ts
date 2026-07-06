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
