# db/dump — JSONLダンプ（自動生成・編集禁止）

このディレクトリは `db/melothea.db`（SQLite正本）から `sqlite-diffable` で生成した
差分可読なダンプです。**編集しないこと。** データの編集対象はSQLite正本のみ
（スキーマ制約が編集時に発火するため。ROADMAPフェーズマイナス1／フェーズ4）。

- 各テーブルにつき `<table>.metadata.json`（列と CREATE TABLE 文）＋ `<table>.ndjson`（1行1レコード）。
- 役割は Git 差分の可読性・保存性・可搬性であり、正本ではない。
- 再生成（正本を変更したら実行）：

  ```
  .venv/bin/sqlite-diffable dump db/melothea.db db/dump \
    entities people groups songs mvs names memberships \
    song_artists song_credits mv_credits mv_songs \
    crew_raw location_raw song_artist_raw mv_artist_raw
  ```

  `--all` は使わない（AUTOINCREMENT由来の予約テーブル `sqlite_sequence` を巻き込み、
  load が予約名で中断するため）。実テーブル15件を明示指定する。

- 注意：ダンプは表レベルの CREATE TABLE（CHECK含む）は保持するが、別オブジェクトの
  索引（`idx_names_primary` 部分ユニーク索引）は保持しない。**正本の再構築は
  `db/schema.sql` を唯一の経路とする**（ダンプからの load はデータ復元用途）。
