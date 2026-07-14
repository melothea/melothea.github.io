-- Melothea MVアーカイブ スキーマ（フェーズ2a）
--
-- 構文検査（スキーマ変更時は毎回通す）：
--   sqlite3 ":memory:" ".read db/schema.sql"
--
-- 主キー方針：
--   entities.id のみ AUTOINCREMENT（公開ID melothea{n} の供給源。削除idの再利用を禁止）
--   people/groups/songs/videos.id は entities(id) を兼ねる素のPK
--   関係テーブル・生記述層は代理キー id INTEGER PRIMARY KEY。UNIQUE当面なし
--
-- 出典：親表ごとの子テーブル（{親表名}_sources）が 1 出典 1 行で保持する（本ファイル末尾）。
--
-- 外部キーは接続ごとに有効化する（下記PRAGMA）。

PRAGMA foreign_keys = ON;

-- ============================================================
-- エンティティ層
-- ============================================================

-- 単一ID空間の発番台帳。id が公開ID melothea{n} の n。
CREATE TABLE entities (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('person','group','song','video'))
);

CREATE TABLE people (
  id                 INTEGER PRIMARY KEY REFERENCES entities(id),
  status             TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published')),
  description        TEXT,
  description_source TEXT CHECK (description_source IN ('ai','manual','ai_edited')),
  wikidata_qid       TEXT,
  mbid               TEXT,
  CHECK (description IS NOT NULL OR description_source IS NULL)  -- 説明文なしにsourceだけを持たない
);

CREATE TABLE groups (
  id                 INTEGER PRIMARY KEY REFERENCES entities(id),
  begin_date         TEXT,                             -- ISO 8601部分日付可。活動開始
  end_date           TEXT,                             -- 活動終了
  ended              INTEGER NOT NULL DEFAULT 0 CHECK (ended IN (0,1)),
  status             TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published')),
  description        TEXT,
  description_source TEXT CHECK (description_source IN ('ai','manual','ai_edited')),
  wikidata_qid       TEXT,
  mbid               TEXT,
  CHECK (description IS NOT NULL OR description_source IS NULL)
);

CREATE TABLE songs (
  id                 INTEGER PRIMARY KEY REFERENCES entities(id),
  release_year       INTEGER,                          -- リリース年は楽曲側
  status             TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published')),
  description        TEXT,
  description_source TEXT CHECK (description_source IN ('ai','manual','ai_edited')),
  wikidata_qid       TEXT,
  mbid               TEXT,
  CHECK (description IS NOT NULL OR description_source IS NULL)
);

CREATE TABLE videos (
  id                 INTEGER PRIMARY KEY REFERENCES entities(id),
  video_type         TEXT,                             -- 種別。NULL可。CI語彙リストで照合（CHECKなし）
  production_year    INTEGER,                          -- 制作年はMV側。楽曲との紐付けはvideo_songs経由
  status             TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published')),
  description        TEXT,
  description_source TEXT CHECK (description_source IN ('ai','manual','ai_edited')),
  wikidata_qid       TEXT,
  mbid               TEXT,
  title_name_id      INTEGER REFERENCES names(id),      -- 代表題の名義行（表示題の基準。既存行はNULL）
  CHECK (description IS NOT NULL OR description_source IS NULL)
);

-- ============================================================
-- names（名義・表記）
-- ============================================================

CREATE TABLE names (
  id                   INTEGER PRIMARY KEY,           -- 内部キー
  entity_id            INTEGER NOT NULL REFERENCES entities(id),
  name_text            TEXT NOT NULL,                 -- 逐語の表記
  lang                 TEXT NOT NULL,                 -- 文字列自体の言語。BCP 47
  locale               TEXT,                          -- 確立形として通用する言語圏。NULL可
  is_primary           INTEGER NOT NULL DEFAULT 0 CHECK (is_primary IN (0,1)),
  name_type            TEXT NOT NULL CHECK (name_type IN ('act_name','legal_name','title')),
  origin               TEXT NOT NULL CHECK (origin IN ('original','adapted')),
  reading              TEXT,                          -- よみ（lang=ja行のひらがな限定）
  derives_from_name_id INTEGER REFERENCES names(id),  -- 由来元の名義行。NULL可
  valid_from           TEXT,                          -- ISO 8601部分日付可
  valid_to             TEXT,
  ended                INTEGER NOT NULL DEFAULT 0 CHECK (ended IN (0,1)),
  CHECK (locale IS NOT NULL OR is_primary = 0)
);
CREATE UNIQUE INDEX idx_names_primary
  ON names(entity_id, locale) WHERE is_primary = 1;

-- ============================================================
-- 関係テーブル（代理キー id）
-- ============================================================
-- 出典は各親表の子テーブル（{親表名}_sources）が持つ。

-- 在籍関係。group_idはgroups直参照、member_idはentities参照（＋CI検証）。
-- UNIQUE(member_id, group_id)は張らない。
CREATE TABLE memberships (
  id        INTEGER PRIMARY KEY,
  group_id  INTEGER NOT NULL REFERENCES groups(id),
  member_id INTEGER NOT NULL REFERENCES entities(id),  -- 人物またはグループ（内包型）
  joined    TEXT,
  "left"    TEXT,                                       -- LEFTは予約語のため引用
  ended     INTEGER NOT NULL DEFAULT 0 CHECK (ended IN (0,1))
);

-- アーティスト名義関係。roleは閉じた語彙（CHECK）。
CREATE TABLE song_artists (
  id               INTEGER PRIMARY KEY,
  song_id          INTEGER NOT NULL REFERENCES songs(id),
  entity_id        INTEGER NOT NULL REFERENCES entities(id),  -- 人物またはグループ（＋CI検証）
  role             TEXT NOT NULL CHECK (role IN ('main','featured')),
  credited_name_id INTEGER REFERENCES names(id)              -- NULL可(未指定＝ビルド時導出)
);

-- 作家クレジット。roleは閉じた語彙（CHECK）。参加者は多態（person/groupのみをCI検証）。
CREATE TABLE song_credits (
  id               INTEGER PRIMARY KEY,
  song_id          INTEGER NOT NULL REFERENCES songs(id),
  entity_id        INTEGER NOT NULL REFERENCES entities(id),
  role             TEXT NOT NULL CHECK (role IN ('lyricist','composer','arranger','producer')),
  credited_name_id INTEGER REFERENCES names(id)
);

-- 映像クレジット。roleは開いた語彙（CHECKなし・CI語彙リストで照合）。
-- role='appearance' ⇒ entity_type='person' はCI検証で強制。
CREATE TABLE video_credits (
  id               INTEGER PRIMARY KEY,
  video_id            INTEGER NOT NULL REFERENCES videos(id),
  entity_id        INTEGER NOT NULL REFERENCES entities(id),
  role             TEXT NOT NULL,
  credited_name_id INTEGER REFERENCES names(id)
);

-- MV×楽曲の中間テーブル。positionはメドレー内順序（通常1）。
CREATE TABLE video_songs (
  id       INTEGER PRIMARY KEY,
  video_id    INTEGER NOT NULL REFERENCES videos(id),
  song_id  INTEGER NOT NULL REFERENCES songs(id),
  position INTEGER NOT NULL
);

CREATE TABLE group_activity_periods (
  id          INTEGER PRIMARY KEY,
  group_id    INTEGER NOT NULL REFERENCES groups(id),
  active_from TEXT,
  active_to   TEXT,
  ended       INTEGER NOT NULL DEFAULT 0 CHECK (ended IN (0,1))
);

-- ============================================================
-- 生記述層（解決リンクはNULL可・後送り）
-- ============================================================

CREATE TABLE crew_raw (
  id        INTEGER PRIMARY KEY,
  video_id     INTEGER NOT NULL REFERENCES videos(id),
  raw_text  TEXT NOT NULL,
  person_id INTEGER REFERENCES people(id)               -- サブタイプ直参照。NULL可（後送り）
);

CREATE TABLE location_raw (
  id          INTEGER PRIMARY KEY,
  video_id       INTEGER NOT NULL REFERENCES videos(id),
  raw_text    TEXT NOT NULL,
  external_id TEXT                                       -- Wikidata/OSM等の外部ID。NULL可
);

CREATE TABLE song_artist_raw (
  id       INTEGER PRIMARY KEY,
  song_id  INTEGER NOT NULL REFERENCES songs(id),
  raw_text TEXT NOT NULL
);

CREATE TABLE video_artist_raw (
  id       INTEGER PRIMARY KEY,
  video_id    INTEGER NOT NULL REFERENCES videos(id),
  raw_text TEXT NOT NULL
);

-- ============================================================
-- 出典層
-- ============================================================
-- 統制語彙。volatile=1 は内容が変わり得る出典（URL・確認日時が意味を持つ）。
CREATE TABLE source_labels (
  label    TEXT PRIMARY KEY,
  volatile INTEGER NOT NULL CHECK (volatile IN (0,1))
);
INSERT INTO source_labels(label, volatile) VALUES
  ('disc',            0),
  ('video_disc',      0),
  ('video_stream',    1),
  ('apple_music',     1),
  ('youtube_music',   1),
  ('official_site',   1),
  ('official_sns',    1),
  ('web_news',        1),
  ('editor_verified', 1);

-- 各親表の出典子テーブル {親表名}_sources。列・CHECKは全10枚に同一に付す。
--   日付   ：referenced_at は disc/video_disc 以外で必須
--   URL    ：disc/video_disc/editor_verified は url NULL、それ以外は url 必須
--   記述子 ：editor_verified は descriptor NULL、それ以外は descriptor 必須
--   記録   ：editor_verified は record_ref 必須（私有記録の参照キー）、それ以外は NULL
CREATE TABLE names_sources (
  id            INTEGER PRIMARY KEY,
  parent_id     INTEGER NOT NULL REFERENCES names(id),
  label         TEXT NOT NULL REFERENCES source_labels(label),
  descriptor    TEXT,
  url           TEXT,
  referenced_at TEXT,                                   -- ISO 8601 YYYY-MM-DD
  record_ref    TEXT,
  CHECK (referenced_at IS NOT NULL OR label IN ('disc','video_disc')),
  CHECK ((label IN ('disc','video_disc','editor_verified') AND url IS NULL)
      OR (label NOT IN ('disc','video_disc','editor_verified') AND url IS NOT NULL)),
  CHECK ((label = 'editor_verified' AND descriptor IS NULL)
      OR (label <> 'editor_verified' AND descriptor IS NOT NULL)),
  CHECK ((label = 'editor_verified' AND record_ref IS NOT NULL)
      OR (label <> 'editor_verified' AND record_ref IS NULL))
);

CREATE TABLE memberships_sources (
  id            INTEGER PRIMARY KEY,
  parent_id     INTEGER NOT NULL REFERENCES memberships(id),
  label         TEXT NOT NULL REFERENCES source_labels(label),
  descriptor    TEXT,
  url           TEXT,
  referenced_at TEXT,
  record_ref    TEXT,
  CHECK (referenced_at IS NOT NULL OR label IN ('disc','video_disc')),
  CHECK ((label IN ('disc','video_disc','editor_verified') AND url IS NULL)
      OR (label NOT IN ('disc','video_disc','editor_verified') AND url IS NOT NULL)),
  CHECK ((label = 'editor_verified' AND descriptor IS NULL)
      OR (label <> 'editor_verified' AND descriptor IS NOT NULL)),
  CHECK ((label = 'editor_verified' AND record_ref IS NOT NULL)
      OR (label <> 'editor_verified' AND record_ref IS NULL))
);

CREATE TABLE group_activity_periods_sources (
  id            INTEGER PRIMARY KEY,
  parent_id     INTEGER NOT NULL REFERENCES group_activity_periods(id),
  label         TEXT NOT NULL REFERENCES source_labels(label),
  descriptor    TEXT,
  url           TEXT,
  referenced_at TEXT,
  record_ref    TEXT,
  CHECK (referenced_at IS NOT NULL OR label IN ('disc','video_disc')),
  CHECK ((label IN ('disc','video_disc','editor_verified') AND url IS NULL)
      OR (label NOT IN ('disc','video_disc','editor_verified') AND url IS NOT NULL)),
  CHECK ((label = 'editor_verified' AND descriptor IS NULL)
      OR (label <> 'editor_verified' AND descriptor IS NOT NULL)),
  CHECK ((label = 'editor_verified' AND record_ref IS NOT NULL)
      OR (label <> 'editor_verified' AND record_ref IS NULL))
);

CREATE TABLE song_artists_sources (
  id            INTEGER PRIMARY KEY,
  parent_id     INTEGER NOT NULL REFERENCES song_artists(id),
  label         TEXT NOT NULL REFERENCES source_labels(label),
  descriptor    TEXT,
  url           TEXT,
  referenced_at TEXT,
  record_ref    TEXT,
  CHECK (referenced_at IS NOT NULL OR label IN ('disc','video_disc')),
  CHECK ((label IN ('disc','video_disc','editor_verified') AND url IS NULL)
      OR (label NOT IN ('disc','video_disc','editor_verified') AND url IS NOT NULL)),
  CHECK ((label = 'editor_verified' AND descriptor IS NULL)
      OR (label <> 'editor_verified' AND descriptor IS NOT NULL)),
  CHECK ((label = 'editor_verified' AND record_ref IS NOT NULL)
      OR (label <> 'editor_verified' AND record_ref IS NULL))
);

CREATE TABLE song_credits_sources (
  id            INTEGER PRIMARY KEY,
  parent_id     INTEGER NOT NULL REFERENCES song_credits(id),
  label         TEXT NOT NULL REFERENCES source_labels(label),
  descriptor    TEXT,
  url           TEXT,
  referenced_at TEXT,
  record_ref    TEXT,
  CHECK (referenced_at IS NOT NULL OR label IN ('disc','video_disc')),
  CHECK ((label IN ('disc','video_disc','editor_verified') AND url IS NULL)
      OR (label NOT IN ('disc','video_disc','editor_verified') AND url IS NOT NULL)),
  CHECK ((label = 'editor_verified' AND descriptor IS NULL)
      OR (label <> 'editor_verified' AND descriptor IS NOT NULL)),
  CHECK ((label = 'editor_verified' AND record_ref IS NOT NULL)
      OR (label <> 'editor_verified' AND record_ref IS NULL))
);

CREATE TABLE video_credits_sources (
  id            INTEGER PRIMARY KEY,
  parent_id     INTEGER NOT NULL REFERENCES video_credits(id),
  label         TEXT NOT NULL REFERENCES source_labels(label),
  descriptor    TEXT,
  url           TEXT,
  referenced_at TEXT,
  record_ref    TEXT,
  CHECK (referenced_at IS NOT NULL OR label IN ('disc','video_disc')),
  CHECK ((label IN ('disc','video_disc','editor_verified') AND url IS NULL)
      OR (label NOT IN ('disc','video_disc','editor_verified') AND url IS NOT NULL)),
  CHECK ((label = 'editor_verified' AND descriptor IS NULL)
      OR (label <> 'editor_verified' AND descriptor IS NOT NULL)),
  CHECK ((label = 'editor_verified' AND record_ref IS NOT NULL)
      OR (label <> 'editor_verified' AND record_ref IS NULL))
);

CREATE TABLE crew_raw_sources (
  id            INTEGER PRIMARY KEY,
  parent_id     INTEGER NOT NULL REFERENCES crew_raw(id),
  label         TEXT NOT NULL REFERENCES source_labels(label),
  descriptor    TEXT,
  url           TEXT,
  referenced_at TEXT,
  record_ref    TEXT,
  CHECK (referenced_at IS NOT NULL OR label IN ('disc','video_disc')),
  CHECK ((label IN ('disc','video_disc','editor_verified') AND url IS NULL)
      OR (label NOT IN ('disc','video_disc','editor_verified') AND url IS NOT NULL)),
  CHECK ((label = 'editor_verified' AND descriptor IS NULL)
      OR (label <> 'editor_verified' AND descriptor IS NOT NULL)),
  CHECK ((label = 'editor_verified' AND record_ref IS NOT NULL)
      OR (label <> 'editor_verified' AND record_ref IS NULL))
);

CREATE TABLE location_raw_sources (
  id            INTEGER PRIMARY KEY,
  parent_id     INTEGER NOT NULL REFERENCES location_raw(id),
  label         TEXT NOT NULL REFERENCES source_labels(label),
  descriptor    TEXT,
  url           TEXT,
  referenced_at TEXT,
  record_ref    TEXT,
  CHECK (referenced_at IS NOT NULL OR label IN ('disc','video_disc')),
  CHECK ((label IN ('disc','video_disc','editor_verified') AND url IS NULL)
      OR (label NOT IN ('disc','video_disc','editor_verified') AND url IS NOT NULL)),
  CHECK ((label = 'editor_verified' AND descriptor IS NULL)
      OR (label <> 'editor_verified' AND descriptor IS NOT NULL)),
  CHECK ((label = 'editor_verified' AND record_ref IS NOT NULL)
      OR (label <> 'editor_verified' AND record_ref IS NULL))
);

CREATE TABLE song_artist_raw_sources (
  id            INTEGER PRIMARY KEY,
  parent_id     INTEGER NOT NULL REFERENCES song_artist_raw(id),
  label         TEXT NOT NULL REFERENCES source_labels(label),
  descriptor    TEXT,
  url           TEXT,
  referenced_at TEXT,
  record_ref    TEXT,
  CHECK (referenced_at IS NOT NULL OR label IN ('disc','video_disc')),
  CHECK ((label IN ('disc','video_disc','editor_verified') AND url IS NULL)
      OR (label NOT IN ('disc','video_disc','editor_verified') AND url IS NOT NULL)),
  CHECK ((label = 'editor_verified' AND descriptor IS NULL)
      OR (label <> 'editor_verified' AND descriptor IS NOT NULL)),
  CHECK ((label = 'editor_verified' AND record_ref IS NOT NULL)
      OR (label <> 'editor_verified' AND record_ref IS NULL))
);

CREATE TABLE video_artist_raw_sources (
  id            INTEGER PRIMARY KEY,
  parent_id     INTEGER NOT NULL REFERENCES video_artist_raw(id),
  label         TEXT NOT NULL REFERENCES source_labels(label),
  descriptor    TEXT,
  url           TEXT,
  referenced_at TEXT,
  record_ref    TEXT,
  CHECK (referenced_at IS NOT NULL OR label IN ('disc','video_disc')),
  CHECK ((label IN ('disc','video_disc','editor_verified') AND url IS NULL)
      OR (label NOT IN ('disc','video_disc','editor_verified') AND url IS NOT NULL)),
  CHECK ((label = 'editor_verified' AND descriptor IS NULL)
      OR (label <> 'editor_verified' AND descriptor IS NOT NULL)),
  CHECK ((label = 'editor_verified' AND record_ref IS NOT NULL)
      OR (label <> 'editor_verified' AND record_ref IS NULL))
);
