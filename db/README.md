# db — Melothea データ層（フェーズ2a）

正本仕様は ai-context リポジトリ（編纂者の私有・非公開、`~/ai-context/mv-ai/`）。本リポジトリにコミットしない。所在と読み順は CLAUDE.md に従う。

## ファイル

| ファイル | 役割 | 編集 |
|---|---|---|
| `schema.sql` | DDL（正本仕様のDDL化）。**正本の再構築経路はこれ** | 手動 |
| `ci_checks.sql` | テーブル間整合のCI検証クエリ（違反行を返すSELECT群） | 手動 |
| `melothea.db` | SQLite正本 | **SQLiteのみが編集対象** |
| `dump/` | JSONLダンプ（自動生成・編集禁止。） | 自動 |

SQLite接続は投入・ビルドとも常に `PRAGMA foreign_keys=ON` を固定する。

## セットアップ（各マシンで一度）

```
# SQLite CLI と venv パッケージ（sudo導入は担当者側）。
# python3.12-venv が無いと ensurepip 欠落で venv 作成が失敗する。
apt install sqlite3 python3.12-venv
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

## スキーマの再構築

スキーマの再構築経路は `db/schema.sql` のみ。データの編集はSQLite正本
（`melothea.db`）に直接行う。データの復元は `dump/` からのロードによる
（後述の「JSONLダンプ」節の記述に従う）。

## CI検証（一行でも返れば失敗）

```
sqlite3 db/melothea.db "PRAGMA foreign_keys=ON;" ".read db/ci_checks.sql"
# 出力が空なら合格。ビルド冒頭で流し、非空ならビルドを失敗させる（手順5〜6で配線）。
```

スキーマ変更時は毎回 `sqlite3 ":memory:" ".read db/schema.sql"` で構文素通しを確認する。

## JSONLダンプ（dump/）

`dump/` は正本から sqlite-diffable で生成した差分可読なダンプ（各テーブルにつき
`<table>.metadata.json` ＋ `<table>.ndjson`）。役割はGit差分の可読性・保存性・
可搬性であり、正本ではない。編集しない。再生成は全消し→正本からの作り直しで、
手順の正本は内部作業文書側で管理する。

- `--all` での生成はSQLiteの内部表 `sqlite_sequence` も出力するが、データモデル外の
  採番状態（AUTOINCREMENT）のため `.gitignore` で追跡外（採番状態は `melothea.db`
  のみが保持する）
- ダンプからの load はデータ復元用途に限る。その際 `sqlite_sequence` は予約名のため
  対象から除く。またダンプは表レベルの CREATE TABLE（CHECK含む）は保持するが
  部分ユニーク索引（`idx_names_primary`）は保持しない——**正本の再構築は
  `db/schema.sql` を唯一の経路とする**
