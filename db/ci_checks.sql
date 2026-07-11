-- Melothea CI検証クエリ（フェーズ2a）
-- 正本：~/ai-context/mv/MV_DATABASE.md「整合の強制と正本運用」
--
-- スキーマ内で張れない「テーブル間整合」を、ビルド冒頭で違反行を返すSELECT群として検査する。
-- 一行でも返ればビルドを失敗させる（公開への唯一の関門）。各行は自己識別できるよう
--   第1列＝check名 / 第2列＝違反行id / 第3列＝該当値 の形で返す。
--
-- 実行（接続ごとにFKも固定。CI検証自体はFK非依存だが運用を統一）：
--   sqlite3 <db> "PRAGMA foreign_keys=ON;" ".read db/ci_checks.sql"
--   出力が1行でもあればビルド失敗（呼び出し側で判定）。
--
-- 検査対象9項目：
--   1 name_type × entity_type / 2 memberships.member型 / 3 credits二表の参加者型 /
--   4 出演個人原則 / 5 derives_from 非循環・同一entity内 / 6 期間の正気度 /
--   7 mv_credits.role・video_type の語彙リスト照合 / 8 完全重複行（二重投入検出） /
--   9 source記述規約の書式検査（4形式適合・禁止トークン不在）

-- ============================================================
-- 0. サブタイプ表 × entity_type の照合
--    サブタイプ表×entity_typeの照合（2026/07/05承認。ER図の検証対象外だったサブタイプ整合を
--    CI側で受ける）。people/groups/songs/mvs.id は entities(id) を参照するがFKは entity_type の
--    一致を強制しないため、entity_type の正しさに依存する項目1〜4の土台としてここで検査する。
-- ============================================================
SELECT 'subtype_entity_type' AS check_name, x.id AS id, x.detail AS detail
FROM (
  SELECT p.id AS id, 'people row but entity_type='||e.entity_type AS detail
    FROM people p JOIN entities e ON e.id = p.id WHERE e.entity_type <> 'person'
  UNION ALL
  SELECT g.id, 'groups row but entity_type='||e.entity_type
    FROM groups g JOIN entities e ON e.id = g.id WHERE e.entity_type <> 'group'
  UNION ALL
  SELECT s.id, 'songs row but entity_type='||e.entity_type
    FROM songs s JOIN entities e ON e.id = s.id WHERE e.entity_type <> 'song'
  UNION ALL
  SELECT m.id, 'mvs row but entity_type='||e.entity_type
    FROM mvs m JOIN entities e ON e.id = m.id WHERE e.entity_type <> 'mv'
) x;

-- ============================================================
-- 1. name_type × entity_type
--    対応表：act_name＝person/group ／ legal_name＝person ／ title＝song
-- ============================================================
SELECT 'name_type_x_entity_type' AS check_name, n.id AS id,
       'name_type='||n.name_type||' entity_type='||e.entity_type||' name='||n.name_text AS detail
FROM names n
JOIN entities e ON e.id = n.entity_id
WHERE NOT (
      (n.name_type = 'act_name'   AND e.entity_type IN ('person','group'))
   OR (n.name_type = 'legal_name' AND e.entity_type = 'person')
   OR (n.name_type = 'title'      AND e.entity_type = 'song')
);

-- ============================================================
-- 2. memberships.member_id の型（person または group のみ）
-- ============================================================
SELECT 'membership_member_type' AS check_name, m.id AS id,
       'member_id='||m.member_id||' entity_type='||e.entity_type AS detail
FROM memberships m
JOIN entities e ON e.id = m.member_id
WHERE e.entity_type NOT IN ('person','group');

-- ============================================================
-- 3. song_credits / mv_credits の参加者型（person または group のみ）
-- ============================================================
SELECT 'song_credit_participant_type' AS check_name, sc.id AS id,
       'entity_id='||sc.entity_id||' entity_type='||e.entity_type||' role='||sc.role AS detail
FROM song_credits sc
JOIN entities e ON e.id = sc.entity_id
WHERE e.entity_type NOT IN ('person','group');

SELECT 'mv_credit_participant_type' AS check_name, mc.id AS id,
       'entity_id='||mc.entity_id||' entity_type='||e.entity_type||' role='||mc.role AS detail
FROM mv_credits mc
JOIN entities e ON e.id = mc.entity_id
WHERE e.entity_type NOT IN ('person','group');

-- song_artists.entity_id も「人物またはグループ」（DATABASE明文：entities参照＋CI検証）。
-- 項目3の列挙漏れを補う（2026/07/05承認）。
SELECT 'song_artist_participant_type' AS check_name, sa.id AS id,
       'entity_id='||sa.entity_id||' entity_type='||e.entity_type||' role='||sa.role AS detail
FROM song_artists sa
JOIN entities e ON e.id = sa.entity_id
WHERE e.entity_type NOT IN ('person','group');

-- ============================================================
-- 4. 出演個人原則（mv_credits.role='appearance' ⇒ entity_type='person'）
-- ============================================================
SELECT 'appearance_must_be_person' AS check_name, mc.id AS id,
       'entity_id='||mc.entity_id||' entity_type='||e.entity_type AS detail
FROM mv_credits mc
JOIN entities e ON e.id = mc.entity_id
WHERE mc.role = 'appearance' AND e.entity_type <> 'person';

-- ============================================================
-- 5a. derives_from_name_id は同一entity内を指す
-- ============================================================
SELECT 'derives_from_cross_entity' AS check_name, n.id AS id,
       'derives_from='||n.derives_from_name_id
       ||' (self entity='||n.entity_id||' target entity='||p.entity_id||')' AS detail
FROM names n
JOIN names p ON p.id = n.derives_from_name_id
WHERE n.entity_id <> p.entity_id;

-- 5b. derives_from の非循環（自己ループ・多段ループの検出）
WITH RECURSIVE walk(start_id, cur_id, depth) AS (
  SELECT id, derives_from_name_id, 1
  FROM names
  WHERE derives_from_name_id IS NOT NULL
  UNION ALL
  SELECT w.start_id, n.derives_from_name_id, w.depth + 1
  FROM walk w
  JOIN names n ON n.id = w.cur_id
  WHERE w.cur_id <> w.start_id           -- 起点に戻ったら展開停止（循環確定）
    AND w.cur_id IS NOT NULL
    AND w.depth < 100                     -- 暴走ガード
)
SELECT 'derives_from_cycle' AS check_name, start_id AS id,
       'cycle back to self within '||depth||' hop(s)' AS detail
FROM walk
WHERE cur_id = start_id;

-- ============================================================
-- 6. 期間の正気度（ISO 8601部分日付は文字列比較で単調）
-- ============================================================
SELECT 'names_period_order' AS check_name, id AS id,
       'valid_from='||valid_from||' > valid_to='||valid_to AS detail
FROM names
WHERE valid_from IS NOT NULL AND valid_to IS NOT NULL AND valid_from > valid_to;

SELECT 'membership_period_order' AS check_name, id AS id,
       'joined='||joined||' > left='||"left" AS detail
FROM memberships
WHERE joined IS NOT NULL AND "left" IS NOT NULL AND joined > "left";

SELECT 'group_period_order' AS check_name, id AS id,
       'begin_date='||begin_date||' > end_date='||end_date AS detail
FROM groups
WHERE begin_date IS NOT NULL AND end_date IS NOT NULL AND begin_date > end_date;

SELECT 'group_activity_period_order' AS check_name, id AS id,
       'active_from='||active_from||' > active_to='||active_to AS detail
FROM group_activity_periods
WHERE active_from IS NOT NULL AND active_to IS NOT NULL AND active_from > active_to;

-- ============================================================
-- 6b. ended 整合（終了日があるのに ended=0）
--     終了日（valid_to／left／end_date）がNOT NULLなら終了済みのはずで ended=1 が整合。
--     DATABASE「endedは終了済み日付不明と継続中の区別」からの解釈による追加（2026/07/05承認。
--     明文なし）。逆（ended=1 かつ日付NULL＝終了済み日付不明）は正当なので検査しない。
-- ============================================================
SELECT 'names_ended_flag' AS check_name, id AS id,
       'valid_to='||valid_to||' but ended=0' AS detail
FROM names
WHERE valid_to IS NOT NULL AND ended = 0;

SELECT 'membership_ended_flag' AS check_name, id AS id,
       'left='||"left"||' but ended=0' AS detail
FROM memberships
WHERE "left" IS NOT NULL AND ended = 0;

SELECT 'group_ended_flag' AS check_name, id AS id,
       'end_date='||end_date||' but ended=0' AS detail
FROM groups
WHERE end_date IS NOT NULL AND ended = 0;

SELECT 'group_activity_ended_flag' AS check_name, id AS id,
       'active_to='||active_to||' but ended=0' AS detail
FROM group_activity_periods
WHERE active_to IS NOT NULL AND ended = 0;

-- ============================================================
-- 7. 語彙リスト照合（観測が増やす開いた語彙。設計側CHECKは張らずここで受ける）
--    当面：mv_credits.role ∈ {director,appearance,choreographer,cinematographer}
--          mvs.video_type ∈ {music_video}（NULLは観測なしとして許容）
-- ============================================================
SELECT 'mv_credit_role_vocab' AS check_name, id AS id, 'role='||role AS detail
FROM mv_credits
WHERE role NOT IN ('director','appearance','choreographer','cinematographer');

SELECT 'video_type_vocab' AS check_name, id AS id, 'video_type='||video_type AS detail
FROM mvs
WHERE video_type IS NOT NULL AND video_type NOT IN ('music_video');

-- ============================================================
-- 8. 完全重複行の検出（id以外の全列一致＝二重投入ミス。近似重複は対象外）
--    各表で全非id列をPARTITIONし、最小id以外を違反として返す。
--    対象は関係テーブル・生記述層・names のみ。エンティティ表（entities/people/groups/songs/mvs）は
--    除外する：draft段階の別エンティティが全列一致し得る（例：属性未入力のpeople行が複数）ため、
--    完全一致を二重投入と断じると正当な別人・別作品を誤検出する。エンティティの重複はid（公開ID）で
--    区別され、内容一致は重複の証拠にならない。
-- ============================================================
SELECT 'dup_row_names' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id,
         MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM names
  WINDOW w AS (PARTITION BY entity_id, name_text, lang, locale, is_primary, name_type,
                            origin, reading, derives_from_name_id, valid_from, valid_to, ended, source)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_memberships' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM memberships
  WINDOW w AS (PARTITION BY group_id, member_id, joined, "left", ended, source)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_song_artists' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM song_artists
  WINDOW w AS (PARTITION BY song_id, entity_id, role, credited_name_id, source)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_song_credits' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM song_credits
  WINDOW w AS (PARTITION BY song_id, entity_id, role, credited_name_id, source)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_mv_credits' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM mv_credits
  WINDOW w AS (PARTITION BY mv_id, entity_id, role, credited_name_id, source)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_mv_songs' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM mv_songs
  WINDOW w AS (PARTITION BY mv_id, song_id, position, source)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_crew_raw' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM crew_raw
  WINDOW w AS (PARTITION BY mv_id, raw_text, source, person_id)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_location_raw' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM location_raw
  WINDOW w AS (PARTITION BY mv_id, raw_text, source, external_id)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_song_artist_raw' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM song_artist_raw
  WINDOW w AS (PARTITION BY song_id, raw_text, source)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_mv_artist_raw' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM mv_artist_raw
  WINDOW w AS (PARTITION BY mv_id, raw_text, source)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_group_activity_periods' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM group_activity_periods
  WINDOW w AS (PARTITION BY group_id, active_from, active_to, ended, source)
) WHERE c > 1 AND id <> first_id;

-- ============================================================
-- 9. source記述規約の書式検査（2026/07/07確定。正本：MV_DATABASE.md「source記述規約」節）
--    source列を持つ全11表（names, memberships, song_artists, song_credits, mv_credits,
--    mv_songs, crew_raw, location_raw, song_artist_raw, mv_artist_raw, group_activity_periods）を対象に、
--    (a) 4形式のいずれにも適合しない行、(b) 禁止トークンを含む行、を違反として返す。
--    有効化は既存行のバックフィル適用後（規約「CI書式検査」細則）。空表は0行で自明に通過する。
--
--    4形式（日付はゼロ埋めYYYY/MM/DD。B・C・DはマーカーをGLOBの[0-9]クラスで検査）：
--      A 一次未確認：B・C・Dマーカーを含まない非空の出典列挙
--      B 一次確認済：「（確認 YYYY/MM/DD）」を含む
--      C 編纂者観察：「（編纂者確認 YYYY/MM/DD）」を含む
--      D 典拠非公開：「（典拠非公開 YYYY/MM/DD、記録R-」を含む
--    形式Aはマーカー接頭辞（（確認 ／（編纂者確認 ／（典拠非公開 ）を含まない非空文字列。
--    これによりマーカーはあるが日付がゼロ埋めでない・不完全な行はB/C/D GLOBに外れ、
--    かつA枝のNOT LIKEに阻まれて違反として捕捉される。旧形式A句（；最終確認先：…（未確認））の
--    残存はA枝を通過するため source_forbidden_token（最終確認先）側で捕捉する。
--    禁止トークン：依頼者 / 要確認 / → / 最終確認先
--    id は表をまたいで衝突するため detail に表名を含めて自己識別させる。
-- ============================================================
SELECT 'source_format' AS check_name, u.id AS id, u.tbl||' source='||u.source AS detail
FROM (
  SELECT 'names' AS tbl, id, source FROM names
  UNION ALL SELECT 'memberships', id, source FROM memberships
  UNION ALL SELECT 'song_artists', id, source FROM song_artists
  UNION ALL SELECT 'song_credits', id, source FROM song_credits
  UNION ALL SELECT 'mv_credits', id, source FROM mv_credits
  UNION ALL SELECT 'mv_songs', id, source FROM mv_songs
  UNION ALL SELECT 'crew_raw', id, source FROM crew_raw
  UNION ALL SELECT 'location_raw', id, source FROM location_raw
  UNION ALL SELECT 'song_artist_raw', id, source FROM song_artist_raw
  UNION ALL SELECT 'mv_artist_raw', id, source FROM mv_artist_raw
  UNION ALL SELECT 'group_activity_periods', id, source FROM group_activity_periods
) u
WHERE NOT (
      u.source GLOB '*（確認 [0-9][0-9][0-9][0-9]/[0-9][0-9]/[0-9][0-9]）*'
   OR u.source GLOB '*（編纂者確認 [0-9][0-9][0-9][0-9]/[0-9][0-9]/[0-9][0-9]）*'
   OR u.source GLOB '*（典拠非公開 [0-9][0-9][0-9][0-9]/[0-9][0-9]/[0-9][0-9]、記録R-*'
   OR ( u.source <> ''
        AND u.source NOT LIKE '%（確認 %'
        AND u.source NOT LIKE '%（編纂者確認 %'
        AND u.source NOT LIKE '%（典拠非公開 %' )
);

SELECT 'source_forbidden_token' AS check_name, u.id AS id, u.tbl||' source='||u.source AS detail
FROM (
  SELECT 'names' AS tbl, id, source FROM names
  UNION ALL SELECT 'memberships', id, source FROM memberships
  UNION ALL SELECT 'song_artists', id, source FROM song_artists
  UNION ALL SELECT 'song_credits', id, source FROM song_credits
  UNION ALL SELECT 'mv_credits', id, source FROM mv_credits
  UNION ALL SELECT 'mv_songs', id, source FROM mv_songs
  UNION ALL SELECT 'crew_raw', id, source FROM crew_raw
  UNION ALL SELECT 'location_raw', id, source FROM location_raw
  UNION ALL SELECT 'song_artist_raw', id, source FROM song_artist_raw
  UNION ALL SELECT 'mv_artist_raw', id, source FROM mv_artist_raw
  UNION ALL SELECT 'group_activity_periods', id, source FROM group_activity_periods
) u
WHERE u.source LIKE '%依頼者%' OR u.source LIKE '%要確認%' OR u.source LIKE '%→%'
   OR u.source LIKE '%最終確認先%';
