// ビルド時のSQLite DBアクセス。
//
// Node 24 標準の node:sqlite を用いる。読み取り専用で開き、接続で foreign_keys を固定する。
// DBは db/melothea.db（JSONLダンプは読まない）。
import { DatabaseSync } from 'node:sqlite';
import { join } from 'node:path';

// プロジェクトルート（cwd）基準で解決する。必要なら MELOTHEA_DB で上書き可能。
const dbPath = process.env.MELOTHEA_DB ?? join(process.cwd(), 'db', 'melothea.db');

const db = new DatabaseSync(dbPath, {
  readOnly: true,
  enableForeignKeyConstraints: true,
});
db.exec('PRAGMA foreign_keys = ON;'); // 接続ごとに固定

export function query<T>(sql: string, ...params: Array<string | number | null>): T[] {
  return db.prepare(sql).all(...params) as T[];
}

export function queryOne<T>(sql: string, ...params: Array<string | number | null>): T | undefined {
  return db.prepare(sql).get(...params) as T | undefined;
}

// ---- 行の型（DDL：db/schema.sql）----

export type EntityType = 'person' | 'group' | 'song' | 'mv';

export interface EntityRow {
  id: number;
  entity_type: EntityType;
}

export interface NameRow {
  id: number;
  entity_id: number;
  name_text: string;
  lang: string;
  locale: string | null;
  is_primary: number;
  name_type: 'act_name' | 'legal_name' | 'title';
  origin: 'original' | 'adapted';
  reading: string | null;
  derives_from_name_id: number | null;
  valid_from: string | null;
  valid_to: string | null;
  ended: number;
}

export interface SongRow {
  id: number;
  release_year: number | null;
  status: string;
}

export interface MvRow {
  id: number;
  video_type: string | null;
  production_year: number | null;
  status: string;
}

export interface SongArtistRow {
  id: number;
  song_id: number;
  entity_id: number;
  role: 'main' | 'featured';
  credited_name_id: number | null;
}

export interface SongCreditRow {
  id: number;
  song_id: number;
  entity_id: number;
  role: 'lyricist' | 'composer' | 'arranger' | 'producer';
  credited_name_id: number | null;
}

export interface MvCreditRow {
  id: number;
  mv_id: number;
  entity_id: number;
  role: string; // 開いた語彙（CI検証で照合）
  credited_name_id: number | null;
}

export interface MvSongRow {
  id: number;
  mv_id: number;
  song_id: number;
  position: number;
}
