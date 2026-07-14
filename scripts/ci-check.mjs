#!/usr/bin/env node
// ビルド/dev の冒頭で回す整合ゲート。
//
// db/ci_checks.sql（違反行を返す SELECT 群）を db/melothea.db に対して流し、一行でも返れば
// ビルドを失敗させる。実行コマンド：
//   sqlite3 db/melothea.db "PRAGMA foreign_keys=ON;" ".read db/ci_checks.sql"
//
// 実行方式は sqlite3 CLI。CLI が無い環境では明示的に失敗させる。

import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const dbPath = join(repoRoot, 'db', 'melothea.db');
const checksPath = join(repoRoot, 'db', 'ci_checks.sql');

for (const [label, p] of [['SQLite DB', dbPath], ['CI検証クエリ', checksPath]]) {
  if (!existsSync(p)) {
    console.error(`CI検証: ${label} が見つかりません: ${p}`);
    process.exit(1);
  }
}

// PRAGMA foreign_keys=ON を接続で固定。
const res = spawnSync(
  'sqlite3',
  [dbPath, 'PRAGMA foreign_keys=ON;', `.read ${checksPath}`],
  { encoding: 'utf8' },
);

if (res.error) {
  if (res.error.code === 'ENOENT') {
    console.error('CI検証: sqlite3 CLI が見つかりません（apt install sqlite3）。検査を飛ばさず失敗させます。');
  } else {
    console.error('CI検証: sqlite3 の起動に失敗:', res.error.message);
  }
  process.exit(1);
}

if (res.status !== 0) {
  console.error('CI検証: sqlite3 が非0終了（SQLエラーの可能性）。');
  if (res.stderr) console.error(res.stderr.trim());
  process.exit(1);
}

if (res.stderr && res.stderr.trim()) {
  // stderr が出ていれば失敗扱いにする。
  console.error('CI検証: sqlite3 が stderr を出力しました（検査クエリのエラー）:');
  console.error(res.stderr.trim());
  process.exit(1);
}

const out = res.stdout.trim();
if (out) {
  console.error('CI検証: 違反行が検出されました（ビルド中止）。各行＝check名|違反行id|該当値:');
  console.error(out);
  process.exit(1);
}

console.log('CI検証: 合格（違反行なし）。');
