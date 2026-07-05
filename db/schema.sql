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
-- source列：一次エンティティのクレジット・生記述は出典明記が質の床（ROADMAPフェーズ3）。
--   names の DDL が source NOT NULL であるのに倣い、関係・生記述表も source NOT NULL とする。
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
  source               TEXT NOT NULL,
  CHECK (locale IS NOT NULL OR is_primary = 0)
);
CREATE UNIQUE INDEX idx_names_primary
  ON names(entity_id, locale) WHERE is_primary = 1;

-- ============================================================
-- 関係テーブル（代理キー id。FK先の使い分けはDATABASE「関係テーブル」節）
-- ============================================================
-- source NOT NULL は残課題「無出典だが依頼者が認識する事実のdraft保持」の余地を狭める決定。
--   無出典保持を採る場合は source を空にせず、出典状態を記述する明示値（例：'no-source:依頼者認識'）で受ける想定。

-- 在籍関係。group_idはgroups直参照、member_idは多態のためentities参照（＋CI検証）。
-- UNIQUE(member_id, group_id)は張らない（脱退→再加入で複数行）。
CREATE TABLE memberships (
  id        INTEGER PRIMARY KEY,
  group_id  INTEGER NOT NULL REFERENCES groups(id),
  member_id INTEGER NOT NULL REFERENCES entities(id),  -- 人物またはグループ（内包型）
  joined    TEXT,
  "left"    TEXT,                                       -- LEFTは予約語のため引用
  ended     INTEGER NOT NULL DEFAULT 0 CHECK (ended IN (0,1)),
  source    TEXT NOT NULL
);

-- アーティスト名義関係。roleは閉じた語彙（CHECK）。
CREATE TABLE song_artists (
  id               INTEGER PRIMARY KEY,
  song_id          INTEGER NOT NULL REFERENCES songs(id),
  entity_id        INTEGER NOT NULL REFERENCES entities(id),  -- 人物またはグループ（＋CI検証）
  role             TEXT NOT NULL CHECK (role IN ('main','featured')),
  credited_name_id INTEGER REFERENCES names(id),             -- NULL可(未指定＝ビルド時導出)
  source           TEXT NOT NULL
);

-- 作家クレジット。roleは閉じた語彙（CHECK）。参加者は多態（person/groupのみをCI検証）。
CREATE TABLE song_credits (
  id               INTEGER PRIMARY KEY,
  song_id          INTEGER NOT NULL REFERENCES songs(id),
  entity_id        INTEGER NOT NULL REFERENCES entities(id),
  role             TEXT NOT NULL CHECK (role IN ('lyricist','composer','arranger','producer')),
  credited_name_id INTEGER REFERENCES names(id),
  source           TEXT NOT NULL
);

-- 映像クレジット。roleは開いた語彙（CHECKなし・CI語彙リストで照合）。
-- role='appearance' ⇒ entity_type='person' はCI検証で強制。
CREATE TABLE mv_credits (
  id               INTEGER PRIMARY KEY,
  mv_id            INTEGER NOT NULL REFERENCES mvs(id),
  entity_id        INTEGER NOT NULL REFERENCES entities(id),
  role             TEXT NOT NULL,
  credited_name_id INTEGER REFERENCES names(id),
  source           TEXT NOT NULL
);

-- MV×楽曲の中間テーブル。positionはメドレー内順序（通常1）。
CREATE TABLE mv_songs (
  id       INTEGER PRIMARY KEY,
  mv_id    INTEGER NOT NULL REFERENCES mvs(id),
  song_id  INTEGER NOT NULL REFERENCES songs(id),
  position INTEGER NOT NULL,
  source   TEXT NOT NULL
);

-- ============================================================
-- 生記述層（保持と解決の分離。解決リンクはNULL可・後送り）
-- ============================================================

CREATE TABLE crew_raw (
  id        INTEGER PRIMARY KEY,
  mv_id     INTEGER NOT NULL REFERENCES mvs(id),
  raw_text  TEXT NOT NULL,
  source    TEXT NOT NULL,
  person_id INTEGER REFERENCES people(id)               -- サブタイプ直参照。NULL可（後送り）
);

CREATE TABLE location_raw (
  id          INTEGER PRIMARY KEY,
  mv_id       INTEGER NOT NULL REFERENCES mvs(id),
  raw_text    TEXT NOT NULL,
  source      TEXT NOT NULL,
  external_id TEXT                                       -- Wikidata/OSM等の外部ID。NULL可
);

CREATE TABLE song_artist_raw (
  id       INTEGER PRIMARY KEY,
  song_id  INTEGER NOT NULL REFERENCES songs(id),
  raw_text TEXT NOT NULL,
  source   TEXT NOT NULL
);

CREATE TABLE mv_artist_raw (
  id       INTEGER PRIMARY KEY,
  mv_id    INTEGER NOT NULL REFERENCES mvs(id),
  raw_text TEXT NOT NULL,
  source   TEXT NOT NULL
);
