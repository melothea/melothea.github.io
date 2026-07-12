-- Melothea MVアーカイブ スキーマ（フェーズ2a）
-- 正本：~/ai-context/mv/MV_DATABASE.md（本ファイルはそのDDL化。乖離に気づいたら実装せず質問）
--
-- 構文検査（スキーマ変更時は毎回通す）：
--   sqlite3 ":memory:" ".read db/schema.sql"
--
-- 語彙の線引き（2026/07/05 承認）：
--   設計が決める閉じた語彙 → スキーマCHECK（本ファイル）
--   観測が増やす開いた語彙 → CI検証の語彙リスト（db/ci_checks.sql、手順2）
--     ・mv_credits.role（当面：director/appearance/choreographer/cinematographer）
--     ・mvs.video_type（当面：music_video）
--
-- 主キー方針（DATABASE「公開IDと内部キーの線引き」／ER図「未規定」を2026/07/05確定）：
--   entities.id のみ AUTOINCREMENT（公開ID melothea{n} の供給源。削除idの再利用を禁止）
--   people/groups/songs/mvs.id は entities(id) を兼ねる素のPK（識別関係）
--   関係テーブル・生記述層は代理キー id INTEGER PRIMARY KEY（ローカル内部キー）。UNIQUE当面なし
--
-- 出典：一次エンティティのクレジット・生記述は出典明記が質の床（ROADMAPフェーズ3）。
--   旧 source 列（各親表の TEXT NOT NULL）は出典層（{親表名}_sources）へ移行して撤去済み。
--   出典は親表ごとの子テーブルが 1 出典 1 行で保持する（本ファイル末尾の出典層を参照）。
--
-- 外部キーはSQLiteでは接続ごとに要有効化。投入スクリプト・ビルドの双方で固定する（下記PRAGMA）。

PRAGMA foreign_keys = ON;

-- ============================================================
-- エンティティ層
-- ============================================================

-- 単一ID空間の発番台帳。id が公開ID melothea{n} の n。
CREATE TABLE entities (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('person','group','song','mv'))
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

CREATE TABLE mvs (
  id                 INTEGER PRIMARY KEY REFERENCES entities(id),
  video_type         TEXT,                             -- 種別。観測できないとき推測で埋めないためNULL可。CI語彙リストで照合（CHECKなし）
  production_year    INTEGER,                          -- 制作年はMV側。楽曲との紐付けはmv_songs経由
  status             TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published')),
  description        TEXT,
  description_source TEXT CHECK (description_source IN ('ai','manual','ai_edited')),
  wikidata_qid       TEXT,
  mbid               TEXT,
  title_name_id      INTEGER REFERENCES names(id),      -- 代表題の名義行（表示題の正本。既存行はNULL）
  CHECK (description IS NOT NULL OR description_source IS NULL)
);

-- ============================================================
-- names（名義・表記。DATABASE のDDLを逐語転記）
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
-- 関係テーブル（代理キー id。FK先の使い分けはDATABASE「関係テーブル」節）
-- ============================================================
-- 出典は各親表の子テーブル（{親表名}_sources）が持つ。旧 source 列は移行して撤去済み。

-- 在籍関係。group_idはgroups直参照、member_idは多態のためentities参照（＋CI検証）。
-- UNIQUE(member_id, group_id)は張らない（脱退→再加入で複数行）。
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
CREATE TABLE mv_credits (
  id               INTEGER PRIMARY KEY,
  mv_id            INTEGER NOT NULL REFERENCES mvs(id),
  entity_id        INTEGER NOT NULL REFERENCES entities(id),
  role             TEXT NOT NULL,
  credited_name_id INTEGER REFERENCES names(id)
);

-- MV×楽曲の中間テーブル。positionはメドレー内順序（通常1）。
CREATE TABLE mv_songs (
  id       INTEGER PRIMARY KEY,
  mv_id    INTEGER NOT NULL REFERENCES mvs(id),
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
-- 生記述層（保持と解決の分離。解決リンクはNULL可・後送り）
-- ============================================================

CREATE TABLE crew_raw (
  id        INTEGER PRIMARY KEY,
  mv_id     INTEGER NOT NULL REFERENCES mvs(id),
  raw_text  TEXT NOT NULL,
  person_id INTEGER REFERENCES people(id)               -- サブタイプ直参照。NULL可（後送り）
);

CREATE TABLE location_raw (
  id          INTEGER PRIMARY KEY,
  mv_id       INTEGER NOT NULL REFERENCES mvs(id),
  raw_text    TEXT NOT NULL,
  external_id TEXT                                       -- Wikidata/OSM等の外部ID。NULL可
);

CREATE TABLE song_artist_raw (
  id       INTEGER PRIMARY KEY,
  song_id  INTEGER NOT NULL REFERENCES songs(id),
  raw_text TEXT NOT NULL
);

CREATE TABLE mv_artist_raw (
  id       INTEGER PRIMARY KEY,
  mv_id    INTEGER NOT NULL REFERENCES mvs(id),
  raw_text TEXT NOT NULL
);

-- ============================================================
-- 出典層（source記述規約の後継。旧 source 列は移行完了・撤去済み）
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
--   日付   ：referenced_at は disc/video_disc 以外で必須（現物確認は確認日を持たない）
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

CREATE TABLE mv_credits_sources (
  id            INTEGER PRIMARY KEY,
  parent_id     INTEGER NOT NULL REFERENCES mv_credits(id),
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

CREATE TABLE mv_artist_raw_sources (
  id            INTEGER PRIMARY KEY,
  parent_id     INTEGER NOT NULL REFERENCES mv_artist_raw(id),
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
