-- Melothea CI検証クエリ（フェーズ2a）
--
-- テーブル間整合を、違反行を返すSELECT群として検査する。一行でも返ればビルド失敗。
-- 各行は 第1列＝check名 / 第2列＝違反行id / 第3列＝該当値 の形で返す。
--
-- 実行：
--   sqlite3 <db> "PRAGMA foreign_keys=ON;" ".read db/ci_checks.sql"
--
-- 検査対象：
--   0 サブタイプ×entity_type / 1 name_type × entity_type（title は楽曲＋被参照MVのみ）/
--   2 memberships.member型 / 3 credits二表の参加者型 / 4 出演個人原則 /
--   5 derives_from 非循環・同一entity内 / 6 期間の正気度 /
--   7 video_credits.role・video_type・release_type の語彙リスト照合／release_dates.date のISO形式 /
--   8 完全重複行（8b：出典付与12表の (parent_id, source_id) 重複） /
--   9 出典層の整合：
--     (a) 子テーブル対象12表の各行に対応する出典子テーブル行が1件以上（video_songs は対象外）
--     (b) source_labels の volatile=0 のラベル集合が {'disc','video_disc'} と一致
--     (c) どの出典子テーブルからも参照されていない sources 行（孤立行）の検出
--     (d) videos.title_name_id の参照先 names が当該MV自身の title 行であること

-- ============================================================
-- 0. サブタイプ表 × entity_type の照合
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
  SELECT m.id, 'videos row but entity_type='||e.entity_type
    FROM videos m JOIN entities e ON e.id = m.id WHERE e.entity_type <> 'video'
) x;

-- ============================================================
-- 1. name_type × entity_type
--    対応表：act_name＝person/group ／ legal_name＝person ／
--            title＝楽曲、および videos.title_name_id から参照されるMV
--            （MVの title 行で被参照でないものは違反）
-- ============================================================
SELECT 'name_type_x_entity_type' AS check_name, n.id AS id,
       'name_type='||n.name_type||' entity_type='||e.entity_type||' name='||n.name_text AS detail
FROM names n
JOIN entities e ON e.id = n.entity_id
WHERE NOT (
      (n.name_type = 'act_name'   AND e.entity_type IN ('person','group'))
   OR (n.name_type = 'legal_name' AND e.entity_type = 'person')
   OR (n.name_type = 'title'      AND e.entity_type = 'song')
   OR (n.name_type = 'title'      AND e.entity_type = 'video'
        AND n.id IN (SELECT title_name_id FROM videos WHERE title_name_id IS NOT NULL))
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
-- 3. song_credits / video_credits の参加者型（person または group のみ）
-- ============================================================
SELECT 'song_credit_participant_type' AS check_name, sc.id AS id,
       'entity_id='||sc.entity_id||' entity_type='||e.entity_type||' role='||sc.role AS detail
FROM song_credits sc
JOIN entities e ON e.id = sc.entity_id
WHERE e.entity_type NOT IN ('person','group');

SELECT 'video_credit_participant_type' AS check_name, mc.id AS id,
       'entity_id='||mc.entity_id||' entity_type='||e.entity_type||' role='||mc.role AS detail
FROM video_credits mc
JOIN entities e ON e.id = mc.entity_id
WHERE e.entity_type NOT IN ('person','group');

-- song_artists.entity_id の型（person または group のみ）
SELECT 'song_artist_participant_type' AS check_name, sa.id AS id,
       'entity_id='||sa.entity_id||' entity_type='||e.entity_type||' role='||sa.role AS detail
FROM song_artists sa
JOIN entities e ON e.id = sa.entity_id
WHERE e.entity_type NOT IN ('person','group');

-- ============================================================
-- 4. 出演個人原則（video_credits.role='appearance' ⇒ entity_type='person'）
-- ============================================================
SELECT 'appearance_must_be_person' AS check_name, mc.id AS id,
       'entity_id='||mc.entity_id||' entity_type='||e.entity_type AS detail
FROM video_credits mc
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
  WHERE w.cur_id <> w.start_id           -- 起点に戻ったら展開停止
    AND w.cur_id IS NOT NULL
    AND w.depth < 100
)
SELECT 'derives_from_cycle' AS check_name, start_id AS id,
       'cycle back to self within '||depth||' hop(s)' AS detail
FROM walk
WHERE cur_id = start_id;

-- ============================================================
-- 6. 期間の正気度
-- ============================================================
SELECT 'names_period_order' AS check_name, id AS id,
       'valid_from='||valid_from||' > valid_to='||valid_to AS detail
FROM names
WHERE valid_from IS NOT NULL AND valid_to IS NOT NULL AND valid_from > valid_to;

SELECT 'membership_period_order' AS check_name, id AS id,
       'membership_from='||membership_from||' > membership_to='||membership_to AS detail
FROM memberships
WHERE membership_from IS NOT NULL AND membership_to IS NOT NULL AND membership_from > membership_to;

SELECT 'group_activity_period_order' AS check_name, id AS id,
       'active_from='||active_from||' > active_to='||active_to AS detail
FROM group_activity_periods
WHERE active_from IS NOT NULL AND active_to IS NOT NULL AND active_from > active_to;

-- ============================================================
-- 6b. ended 整合（終了日があるのに ended=0）
-- ============================================================
SELECT 'names_ended_flag' AS check_name, id AS id,
       'valid_to='||valid_to||' but ended=0' AS detail
FROM names
WHERE valid_to IS NOT NULL AND ended = 0;

SELECT 'membership_ended_flag' AS check_name, id AS id,
       'membership_to='||membership_to||' but ended=0' AS detail
FROM memberships
WHERE membership_to IS NOT NULL AND ended = 0;

SELECT 'group_activity_ended_flag' AS check_name, id AS id,
       'active_to='||active_to||' but ended=0' AS detail
FROM group_activity_periods
WHERE active_to IS NOT NULL AND ended = 0;

-- ============================================================
-- 7. 語彙リスト照合
--    video_credits.role ∈ {director,appearance,choreographer,cinematographer}
--    videos.video_type ∈ {music_video}（NULLは許容）
-- ============================================================
SELECT 'video_credit_role_vocab' AS check_name, id AS id, 'role='||role AS detail
FROM video_credits
WHERE role NOT IN ('director','appearance','choreographer','cinematographer');

SELECT 'video_type_vocab' AS check_name, id AS id, 'video_type='||video_type AS detail
FROM videos
WHERE video_type IS NOT NULL AND video_type NOT IN ('music_video');

-- release_type 語彙リスト照合（許可リストは空。NOT NULL の release_type はすべて違反）。
-- 語彙の初出時に「AND release_type NOT IN ('新語彙', ...)」を付して許可リストへ加算する。
SELECT 'song_release_type_vocab' AS check_name, id AS id, 'release_type='||release_type AS detail
FROM song_release_dates
WHERE release_type IS NOT NULL;

SELECT 'video_release_type_vocab' AS check_name, id AS id, 'release_type='||release_type AS detail
FROM video_release_dates
WHERE release_type IS NOT NULL;

-- date 形式検査：ISO 8601部分日付（YYYY／YYYY-MM／YYYY-MM-DD）のいずれにも適合しない行を返す。
SELECT 'song_release_date_format' AS check_name, id AS id, 'date='||date AS detail
FROM song_release_dates
WHERE NOT (date GLOB '[0-9][0-9][0-9][0-9]'
        OR date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]'
        OR date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]');

SELECT 'video_release_date_format' AS check_name, id AS id, 'date='||date AS detail
FROM video_release_dates
WHERE NOT (date GLOB '[0-9][0-9][0-9][0-9]'
        OR date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]'
        OR date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]');

-- ============================================================
-- 8. 完全重複行の検出（id以外の全列一致＝二重投入ミス）
--    各表で全非id列をPARTITIONし、最小id以外を違反として返す。
--    対象は関係テーブル・生記述層・names と、出典子テーブル10枚。エンティティ表は除外。
-- ============================================================
SELECT 'dup_row_names' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id,
         MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM names
  WINDOW w AS (PARTITION BY entity_id, name_text, lang, locale, is_primary, name_type,
                            origin, reading, derives_from_name_id, valid_from, valid_to, ended)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_memberships' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM memberships
  WINDOW w AS (PARTITION BY group_id, member_id, membership_from, membership_to, ended)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_song_artists' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM song_artists
  WINDOW w AS (PARTITION BY song_id, entity_id, role, credited_name_id)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_song_credits' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM song_credits
  WINDOW w AS (PARTITION BY song_id, entity_id, role, credited_name_id)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_mv_credits' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM video_credits
  WINDOW w AS (PARTITION BY video_id, entity_id, role, credited_name_id)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_mv_songs' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM video_songs
  WINDOW w AS (PARTITION BY video_id, song_id, position)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_crew_raw' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM crew_raw
  WINDOW w AS (PARTITION BY video_id, raw_text, person_id)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_location_raw' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM location_raw
  WINDOW w AS (PARTITION BY video_id, raw_text, external_id)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_song_artist_raw' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM song_artist_raw
  WINDOW w AS (PARTITION BY song_id, raw_text)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_mv_artist_raw' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM video_artist_raw
  WINDOW w AS (PARTITION BY video_id, raw_text)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_group_activity_periods' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM group_activity_periods
  WINDOW w AS (PARTITION BY group_id, active_from, active_to, ended)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_song_release_dates' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM song_release_dates
  WINDOW w AS (PARTITION BY song_id, date, release_type)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_video_release_dates' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM video_release_dates
  WINDOW w AS (PARTITION BY video_id, date, release_type)
) WHERE c > 1 AND id <> first_id;

-- --- 8b. 出典子テーブル12枚の (parent_id, source_id) 重複行 ---
--    非id列がこの2列のみのため、完全重複行検出＝同一出典の重複付与検出と等価。
SELECT 'dup_row_names_sources' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM names_sources
  WINDOW w AS (PARTITION BY parent_id, source_id)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_memberships_sources' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM memberships_sources
  WINDOW w AS (PARTITION BY parent_id, source_id)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_group_activity_periods_sources' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM group_activity_periods_sources
  WINDOW w AS (PARTITION BY parent_id, source_id)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_song_artists_sources' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM song_artists_sources
  WINDOW w AS (PARTITION BY parent_id, source_id)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_song_credits_sources' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM song_credits_sources
  WINDOW w AS (PARTITION BY parent_id, source_id)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_mv_credits_sources' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM video_credits_sources
  WINDOW w AS (PARTITION BY parent_id, source_id)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_crew_raw_sources' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM crew_raw_sources
  WINDOW w AS (PARTITION BY parent_id, source_id)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_location_raw_sources' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM location_raw_sources
  WINDOW w AS (PARTITION BY parent_id, source_id)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_song_artist_raw_sources' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM song_artist_raw_sources
  WINDOW w AS (PARTITION BY parent_id, source_id)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_mv_artist_raw_sources' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM video_artist_raw_sources
  WINDOW w AS (PARTITION BY parent_id, source_id)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_song_release_dates_sources' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM song_release_dates_sources
  WINDOW w AS (PARTITION BY parent_id, source_id)
) WHERE c > 1 AND id <> first_id;

SELECT 'dup_row_video_release_dates_sources' AS check_name, id AS id, 'duplicate of id '||first_id AS detail
FROM (
  SELECT id, MIN(id) OVER w AS first_id, COUNT(*) OVER w AS c
  FROM video_release_dates_sources
  WINDOW w AS (PARTITION BY parent_id, source_id)
) WHERE c > 1 AND id <> first_id;

-- ============================================================
-- 9. 出典層の整合
-- ============================================================

-- (a) 子テーブル対象12表の各行に、対応する出典子テーブル行が1件以上存在すること。
--     video_songs は出典子テーブルを持たない（対象外）。親行に出典が1件も無ければ違反。
SELECT 'missing_source_names' AS check_name, n.id AS id, 'no names_sources row' AS detail
FROM names n WHERE NOT EXISTS (SELECT 1 FROM names_sources s WHERE s.parent_id = n.id);

SELECT 'missing_source_memberships' AS check_name, m.id AS id, 'no memberships_sources row' AS detail
FROM memberships m WHERE NOT EXISTS (SELECT 1 FROM memberships_sources s WHERE s.parent_id = m.id);

SELECT 'missing_source_group_activity_periods' AS check_name, g.id AS id, 'no group_activity_periods_sources row' AS detail
FROM group_activity_periods g WHERE NOT EXISTS (SELECT 1 FROM group_activity_periods_sources s WHERE s.parent_id = g.id);

SELECT 'missing_source_song_artists' AS check_name, a.id AS id, 'no song_artists_sources row' AS detail
FROM song_artists a WHERE NOT EXISTS (SELECT 1 FROM song_artists_sources s WHERE s.parent_id = a.id);

SELECT 'missing_source_song_credits' AS check_name, c.id AS id, 'no song_credits_sources row' AS detail
FROM song_credits c WHERE NOT EXISTS (SELECT 1 FROM song_credits_sources s WHERE s.parent_id = c.id);

SELECT 'missing_source_mv_credits' AS check_name, c.id AS id, 'no video_credits_sources row' AS detail
FROM video_credits c WHERE NOT EXISTS (SELECT 1 FROM video_credits_sources s WHERE s.parent_id = c.id);

SELECT 'missing_source_crew_raw' AS check_name, r.id AS id, 'no crew_raw_sources row' AS detail
FROM crew_raw r WHERE NOT EXISTS (SELECT 1 FROM crew_raw_sources s WHERE s.parent_id = r.id);

SELECT 'missing_source_location_raw' AS check_name, r.id AS id, 'no location_raw_sources row' AS detail
FROM location_raw r WHERE NOT EXISTS (SELECT 1 FROM location_raw_sources s WHERE s.parent_id = r.id);

SELECT 'missing_source_song_artist_raw' AS check_name, r.id AS id, 'no song_artist_raw_sources row' AS detail
FROM song_artist_raw r WHERE NOT EXISTS (SELECT 1 FROM song_artist_raw_sources s WHERE s.parent_id = r.id);

SELECT 'missing_source_mv_artist_raw' AS check_name, r.id AS id, 'no video_artist_raw_sources row' AS detail
FROM video_artist_raw r WHERE NOT EXISTS (SELECT 1 FROM video_artist_raw_sources s WHERE s.parent_id = r.id);

SELECT 'missing_source_song_release_dates' AS check_name, r.id AS id, 'no song_release_dates_sources row' AS detail
FROM song_release_dates r WHERE NOT EXISTS (SELECT 1 FROM song_release_dates_sources s WHERE s.parent_id = r.id);

SELECT 'missing_source_video_release_dates' AS check_name, r.id AS id, 'no video_release_dates_sources row' AS detail
FROM video_release_dates r WHERE NOT EXISTS (SELECT 1 FROM video_release_dates_sources s WHERE s.parent_id = r.id);

-- (b) source_labels の volatile=0（固定資料）のラベル集合が {'disc','video_disc'} と一致すること。
--     固定資料ラベルを増やした場合は下記の検査集合も同時に更新する。
--     集合差（余分な volatile=0／不足）があれば1行返す。
SELECT 'volatile_zero_label_set' AS check_name, 0 AS id,
       'volatile=0 set='||COALESCE((SELECT group_concat(label, ',')
                                    FROM (SELECT label FROM source_labels WHERE volatile = 0 ORDER BY label)),
                                   '(empty)')||' expected=disc,video_disc' AS detail
WHERE EXISTS (SELECT 1 FROM source_labels WHERE volatile = 0 AND label NOT IN ('disc','video_disc'))
   OR EXISTS (SELECT 1 FROM source_labels WHERE label IN ('disc','video_disc') AND (volatile <> 0 OR volatile IS NULL))
   OR (SELECT count(*) FROM source_labels WHERE volatile = 0) <> 2;

-- (c) どの出典子テーブルからも参照されていない sources 行（孤立行）の検出。
SELECT 'orphan_source' AS check_name, s.id AS id,
       'label='||s.label||' url='||COALESCE(s.url,'')||' record_ref='||COALESCE(s.record_ref,'') AS detail
FROM sources s
WHERE NOT EXISTS (SELECT 1 FROM names_sources t WHERE t.source_id = s.id)
  AND NOT EXISTS (SELECT 1 FROM memberships_sources t WHERE t.source_id = s.id)
  AND NOT EXISTS (SELECT 1 FROM group_activity_periods_sources t WHERE t.source_id = s.id)
  AND NOT EXISTS (SELECT 1 FROM song_artists_sources t WHERE t.source_id = s.id)
  AND NOT EXISTS (SELECT 1 FROM song_credits_sources t WHERE t.source_id = s.id)
  AND NOT EXISTS (SELECT 1 FROM video_credits_sources t WHERE t.source_id = s.id)
  AND NOT EXISTS (SELECT 1 FROM song_release_dates_sources t WHERE t.source_id = s.id)
  AND NOT EXISTS (SELECT 1 FROM video_release_dates_sources t WHERE t.source_id = s.id)
  AND NOT EXISTS (SELECT 1 FROM crew_raw_sources t WHERE t.source_id = s.id)
  AND NOT EXISTS (SELECT 1 FROM location_raw_sources t WHERE t.source_id = s.id)
  AND NOT EXISTS (SELECT 1 FROM song_artist_raw_sources t WHERE t.source_id = s.id)
  AND NOT EXISTS (SELECT 1 FROM video_artist_raw_sources t WHERE t.source_id = s.id);

-- (d) videos.title_name_id が非NULLなら、参照先 names 行の entity_id が当該MV自身であり
--     name_type='title' であること。
SELECT 'title_name_id_integrity' AS check_name, m.id AS id,
       'title_name_id='||m.title_name_id||' -> name entity='||n.entity_id
       ||' name_type='||n.name_type AS detail
FROM videos m
JOIN names n ON n.id = m.title_name_id
WHERE m.title_name_id IS NOT NULL
  AND (n.entity_id <> m.id OR n.name_type <> 'title');
