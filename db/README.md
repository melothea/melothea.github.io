# db — Melothea データ層（フェーズ2a）

正本仕様は `~/ai-context/mv/MV_DATABASE.md`（本リポジトリにコミットしない。CLAUDE.md参照）。

## ファイル

| ファイル | 役割 | 編集 |
|---|---|---|
| `schema.sql` | DDL（正本仕様のDDL化）。**正本の再構築経路はこれ** | 手動 |
| `ci_checks.sql` | テーブル間整合のCI検証クエリ（違反行を返すSELECT群） | 手動 |
| `seed.sql` | フェーズ2a シード（CS Channel期3本） | 手動 |
| `melothea.db` | SQLite正本（schema→seed から生成） | **SQLiteのみが編集対象** |
| `dump/` | JSONLダンプ（自動生成・編集禁止。`dump/README.md`参照） | 自動 |

SQLite接続は投入・ビルドとも常に `PRAGMA foreign_keys=ON` を固定する。

## セットアップ（各マシンで一度）

```
# SQLite CLI と venv パッケージ（sudo導入は担当者側）。
# python3.12-venv が無いと ensurepip 欠落で venv 作成が失敗する。
apt install sqlite3 python3.12-venv
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

## 正本の再構築（schema→seed）

```
rm -f db/melothea.db
sqlite3 db/melothea.db "PRAGMA foreign_keys=ON;" ".read db/schema.sql" ".read db/seed.sql"
```

**但し書き：この手順はフェーズ2a初期構築の再現専用。** 正本（`melothea.db`）に直接編集が
入った後に実行すると、その編集が失われる。以後のデータ編集はSQLite正本に直接行い（制約が
編集時に発火するため）、`seed.sql` は初期投入の履歴として凍結する（正本運用：DATABASE
「整合の強制と正本運用」——正本の編集対象はSQLiteのみ）。

## CI検証（一行でも返れば失敗）

```
sqlite3 db/melothea.db "PRAGMA foreign_keys=ON;" ".read db/ci_checks.sql"
# 出力が空なら合格。ビルド冒頭で流し、非空ならビルドを失敗させる（手順5〜6で配線）。
```

スキーマ変更時は毎回 `sqlite3 ":memory:" ".read db/schema.sql"` で構文素通しを確認する。

## JSONLダンプの再生成

`dump/README.md` のコマンド（実テーブル15件を明示指定。`--all` は使わない）。
