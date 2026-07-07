// @ts-check
import { defineConfig } from 'astro/config';

// URL設計の正本：~/ai-context/mv/MV_ROADMAP.md フェーズ0「URL設計」（乖離に気づいたら実装せず質問）
//   ・正準ドメイン＝apex（melothea.org）。site はビルド時の絶対URL（canonical / hreflang）に効く
//   ・末尾形式＝ディレクトリ形式・末尾スラッシュ（build.format:'directory' ＋ trailingSlash:'always'）。
//     .html を URI に出さない＝実装技術をURIに含めない
//   ・言語ページ＝/{lang}/melothea{n}/（ja/en。既定言語も接頭辞を付ける＝既定言語という可変属性を
//     URL契約に焼き込まない。ID体系と同一原理）
//   ・実体URI＝/melothea{n}/（言語中立ハブ。末尾スラッシュ規則を全経路で統一。スラッシュなし
//     アクセスの実挙動確認はテストデプロイ時＝手順6の残タスク）
export default defineConfig({
  // 疎通段階の暫定値。カスタムドメイン(melothea.org)設定時に apex へ戻す（手順6後半）。
  site: 'https://melothea.github.io',
  trailingSlash: 'always',
  build: { format: 'directory' },
  i18n: {
    defaultLocale: 'ja',
    locales: ['ja', 'en'],
    // 既定言語も接頭辞を付ける（無接頭辞の既定言語ページを作らない）。ページ生成は各ページの
    // getStaticPaths（[lang] 明示）で全面制御し、Astro の自動ルート生成には依存しない。
    routing: { prefixDefaultLocale: true },
  },
});
