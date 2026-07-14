-- Melothea シードデータ（フェーズ2a：CS Channel期3本）草案
--
-- ID は明示指定で投入する（melothea1..13）。

PRAGMA foreign_keys = ON;

-- ============================================================
-- entities（13件）＋ サブタイプ
-- ============================================================
INSERT INTO entities(id, entity_type) VALUES
  (1,'person'),   -- 児玉裕一
  (2,'person'),   -- 椎名林檎
  (3,'person'),   -- 亀田誠治
  (4,'person'),   -- 浮雲
  (5,'person'),   -- 伊澤一葉
  (6,'person'),   -- 刄田綴色
  (7,'group'),    -- 東京事変
  (8,'song'),     -- 能動的三分間
  (9,'song'),     -- 空が鳴っている
  (10,'song'),    -- ハンサム過ぎて
  (11,'mv'),      -- 能動的三分間 MV
  (12,'mv'),      -- 空が鳴っている MV
  (13,'mv');      -- ハンサム過ぎて MV

INSERT INTO people(id) VALUES (1),(2),(3),(4),(5),(6);

-- 東京事変の活動期間（begin/end）は2a範囲外。NULLで投入。
INSERT INTO groups(id) VALUES (7);

INSERT INTO songs(id, release_year) VALUES
  (8, 2009),      -- 能動的三分間
  (9, 2011),      -- 空が鳴っている
  (10, 2011);     -- ハンサム過ぎて

INSERT INTO mvs(id, video_type, production_year) VALUES
  (11, 'music_video', 2009),
  (12, 'music_video', 2011),
  (13, 'music_video', 2011);

-- ============================================================
-- names（各エンティティの ja primary。act_name＝人物/グループ、title＝楽曲）
--   reading は全行NULL。origin=original、locale=ja、is_primary=1。
-- ============================================================
INSERT INTO names(id, entity_id, name_text, lang, locale, is_primary, name_type, origin, source) VALUES
  (1, 1, '児玉裕一',   'ja','ja',1,'act_name','original','rockinon.com 2011/8/31記事（全名・全題の逐語表記）→ vivisionプロフィール（公式表記）'),
  (2, 2, '椎名林檎',   'ja','ja',1,'act_name','original','rockinon.com 2011/8/31記事（全名・全題の逐語表記）→ 東京事変公式サイト等の公式表記'),
  (3, 3, '亀田誠治',   'ja','ja',1,'act_name','original','rockinon.com 2011/8/31記事（全名・全題の逐語表記）→ 東京事変公式サイト等の公式表記'),
  (4, 4, '浮雲',       'ja','ja',1,'act_name','original','rockinon.com 2011/8/31記事（全名・全題の逐語表記）→ 東京事変公式サイト等の公式表記'),
  (5, 5, '伊澤一葉',   'ja','ja',1,'act_name','original','rockinon.com 2011/8/31記事（全名・全題の逐語表記）→ 東京事変公式サイト等の公式表記'),
  (6, 6, '刄田綴色',   'ja','ja',1,'act_name','original','rockinon.com 2011/8/31記事（全名・全題の逐語表記）→ 東京事変公式サイト等の公式表記'),
  (7, 7, '東京事変',   'ja','ja',1,'act_name','original','rockinon.com 2011/8/31記事（全名・全題の逐語表記）→ 東京事変公式サイト等の公式表記'),
  (8, 8, '能動的三分間','ja','ja',1,'title','original','rockinon.com 2011/8/31記事（全名・全題の逐語表記）→ 映像本体・公式ディスコグラフィ'),
  (9, 9, '空が鳴っている','ja','ja',1,'title','original','rockinon.com 2011/8/31記事（全名・全題の逐語表記）→ 映像本体・公式ディスコグラフィ'),
  (10,10,'ハンサム過ぎて','ja','ja',1,'title','original','rockinon.com 2011/8/31記事（全名・全題の逐語表記）→ 映像本体・公式ディスコグラフィ');

-- ============================================================
-- song_artists（main：東京事変）
-- ============================================================
INSERT INTO song_artists(song_id, entity_id, role, source) VALUES
  (8, 7, 'main', '収録盤 → 映像本体'),
  (9, 7, 'main', '収録盤 → 映像本体'),
  (10,7, 'main', '収録盤 → 映像本体');

-- ============================================================
-- song_credits
-- ============================================================
INSERT INTO song_credits(song_id, entity_id, role, source) VALUES
  (8, 2, 'lyricist', '歌ネット（NexTone許諾表記あり）→ 収録盤ブックレット'),
  (8, 2, 'composer', '歌ネット（NexTone許諾表記あり）→ 収録盤ブックレット'),
  (8, 7, 'arranger', '歌ネット「編曲：東京事変」（版未特定）→ 最終確認時に音源収録盤ブックレット（シングル盤／アルバム）で版を特定'),
  (9, 2, 'lyricist', '歌ネット・記憶の記録LIBRARY → 収録盤ブックレット'),
  (9, 3, 'composer', '歌ネット・記憶の記録LIBRARY → 収録盤ブックレット'),
  (9, 7, 'arranger', '歌ネット「編曲：東京事変」（版未特定）→ 最終確認時に音源収録盤ブックレット（シングル盤／アルバム）で版を特定'),
  (10,1, 'lyricist', '歌ネット・J-Lyric、rockinon.com 2011/8/31（椎名林檎作曲・児玉裕一作詞と明記）→ 収録盤ブックレット'),
  (10,2, 'composer', '歌ネット・J-Lyric、rockinon.com 2011/8/31（椎名林檎作曲・児玉裕一作詞と明記）→ 収録盤ブックレット');
  -- S3 arranger は未取得。

-- ============================================================
-- mv_credits
--   credited_name_id は全行NULL（浮雲は names 投入後にUPDATE）。
-- ============================================================
INSERT INTO mv_credits(mv_id, entity_id, role, source) VALUES
  -- director
  (11, 1, 'director', '能動的三分間Wikipedia＋東京事変公式サイト オフィシャル・インタビュー → 映像本体'),
  (12, 1, 'director', 'CS Channel一括報道（タワーレコードニュース2011/7/15、rockinon.com 2011/8/31収録一覧）→ 映像本体'),
  (13, 1, 'director', 'rockinon.com 2011/8/31 → 映像本体'),
  -- appearance
  (11, 2, 'appearance', '公式インタビュー（PVでのムーンウォーク言及）→ 映像本体（他メンバー4人の出演は要確認）'),
  (12, 2, 'appearance', '当時のメンバー全員（依頼者確認2026/07/05）→ 映像本体'),
  (12, 3, 'appearance', '当時のメンバー全員（依頼者確認2026/07/05）→ 映像本体'),
  (12, 4, 'appearance', '当時のメンバー全員（依頼者確認2026/07/05）→ 映像本体（クレジット逐語＝当時名義の表記を最終確認。浮雲は併存名義のため明示指定）'),
  (12, 5, 'appearance', '当時のメンバー全員（依頼者確認2026/07/05）→ 映像本体'),
  (12, 6, 'appearance', '当時のメンバー全員（依頼者確認2026/07/05）→ 映像本体'),
  (13, 2, 'appearance', 'rockinon.com 2011/8/31（TVキャスターに扮する椎名林檎）→ 映像本体'),
  (13, 3, 'appearance', 'rockinon.com 2011/8/31（亀田誠治・浮雲・伊澤一葉・刄田綴色が演技）→ 映像本体'),
  (13, 4, 'appearance', 'rockinon.com 2011/8/31（亀田誠治・浮雲・伊澤一葉・刄田綴色が演技）→ 映像本体'),  -- 浮雲：credited_name_id 明示指定を names 投入後に付与
  (13, 5, 'appearance', 'rockinon.com 2011/8/31（亀田誠治・浮雲・伊澤一葉・刄田綴色が演技）→ 映像本体'),
  (13, 6, 'appearance', 'rockinon.com 2011/8/31（亀田誠治・浮雲・伊澤一葉・刄田綴色が演技）→ 映像本体');

-- ============================================================
-- mv_songs（各 position=1）
-- ============================================================
INSERT INTO mv_songs(mv_id, song_id, position, source) VALUES
  (11, 8, 1, 'CS Channel収録事実（タワーレコードニュース2011/7/15等）→ 映像本体'),
  (12, 9, 1, 'CS Channel収録事実（タワーレコードニュース2011/7/15等）→ 映像本体'),
  (13,10, 1, 'CS Channel収録事実（タワーレコードニュース2011/7/15等）→ 映像本体');

-- ============================================================
-- 浮雲の当時名義の明示指定。
--   M2(mv=12)・M3(mv=13) の浮雲(entity=4) appearance 行を浮雲名義行(names.id=4)に結線。
-- ============================================================
UPDATE mv_credits
   SET credited_name_id = 4
 WHERE role = 'appearance' AND entity_id = 4 AND mv_id IN (12, 13);
