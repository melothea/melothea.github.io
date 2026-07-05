// 名義表示の4段カスケード（正本：~/ai-context/mv/MV_DATABASE.md「表示の二水準と4段カスケード」）。
// ビルド時導出。導出値はDBに書き込まない。
//
// 二水準：
//   ・クレジット文脈（作品ページのクレジット欄）＝当該クレジットが指す名義行が錨。逐語を常に保持。
//   ・人物文脈（見出し・一覧・リンクテキスト）＝人物エンティティが錨。
//
// カスケード（主表示の決定）：
//   1. 逐語（クレジット文脈では常に保持・表示）
//   2. ページ言語localeの確立形。
//        クレジット文脈：クレジット名義に対応する系列＝derives_from 参照を優先（確定仕様）。
//          確立形行がクレジット逐語行と derives_from 連結（同一系列。自己参照は自明に連結）である
//          ことを確認してから採用し、系列不一致なら採用せず次段へ倒す。これは百瀬ひなの型判定
//          （旧名義のクレジットに現名義系列の確立形を出さない）のフェーズ1確定判定の実装であって、
//          将来の細則拡張ではない。
//        人物文脈：人物の locale別 primary を直取り（錨が人物エンティティのため系列条件は付かない）。
//   3. 言語別フォールバック（細則はフェーズ2残課題。ja/en では該当なし＝未発火）。
//   4. 導出転写。発火条件：origin='original' かつ、文字体系が自足的（ハングル・キリル等）なら name_text、
//      ja（漢字かな交じり）なら reading を入力。reading が NULL なら発火せず、逐語＋人物リンクに落ちる
//      （粗悪な代用を出さず劣化する）。
//
// 本スライス（CS Channel期3本）の実データは全名義が lang=ja・locale=ja・is_primary=1・reading=NULL・
// origin=original で derives_from なし。したがって：
//   ・ja ページ：2段目の確立形候補（locale=ja primary）が逐語行そのもの＝自己連結で採用される。
//   ・en ページ：locale=en 行が無く2段目不発火、reading=NULL で4段目も不発火 → 逐語（lang=ja）＋
//     人物リンクに劣化する。
// 両分岐とも本実装で実際に通す。

import { query, type NameRow } from './db.ts';

export type Lang = 'ja' | 'en';

export interface Rendered {
  /** 主表示（確立形＞導出＞逐語 の順で決まる） */
  main: { text: string; lang: string };
  /** 併記（クレジット文脈で主表示が逐語でないとき、実クレジットの逐語を併記する） */
  sub?: { text: string; lang: string };
  /** 主表示が逐語そのもの（確立形も導出も無く劣化した）か */
  degraded: boolean;
  /** リンク先エンティティ（人物文脈への錨）。/melothea{linkId}/ */
  linkId: number;
}

function namesOf(entityId: number): NameRow[] {
  return query<NameRow>('SELECT * FROM names WHERE entity_id = ? ORDER BY id', entityId);
}

function nameById(id: number): NameRow | undefined {
  return query<NameRow>('SELECT * FROM names WHERE id = ?', id)[0];
}

/** 人物文脈の2段目：ページ言語localeの primary（系列条件なし。錨が人物エンティティのため）。 */
function localePrimary(entityId: number, lang: Lang): NameRow | undefined {
  return query<NameRow>(
    'SELECT * FROM names WHERE entity_id = ? AND locale = ? AND is_primary = 1 ORDER BY id LIMIT 1',
    entityId,
    lang,
  )[0];
}

/** aId と bId が同一 entity 内で derives_from によって連結された同一系列か。
 *  自己参照（aId===bId）は自明に連結。derives_from は無向連結成分として扱う
 *  （CI検証が同一entity内・非循環を保証するため終端する）。 */
function sameSeries(entityId: number, aId: number, bId: number): boolean {
  if (aId === bId) return true;
  const adj = new Map<number, number[]>();
  const link = (x: number, y: number) => {
    const a = adj.get(x);
    if (a) a.push(y);
    else adj.set(x, [y]);
  };
  for (const r of namesOf(entityId)) {
    if (r.derives_from_name_id != null) {
      link(r.id, r.derives_from_name_id);
      link(r.derives_from_name_id, r.id);
    }
  }
  const seen = new Set<number>([aId]);
  const stack = [aId];
  while (stack.length) {
    const cur = stack.pop()!;
    if (cur === bId) return true;
    for (const nx of adj.get(cur) ?? []) {
      if (!seen.has(nx)) {
        seen.add(nx);
        stack.push(nx);
      }
    }
  }
  return false;
}

/** クレジット文脈の2段目：ページ言語localeの確立形のうち、クレジット逐語行と同一系列のものを採用
 *  （primary を優先）。系列一致が無ければ undefined＝次段へ倒す。 */
function establishedInSeries(entityId: number, lang: Lang, verbatimId: number): NameRow | undefined {
  const candidates = query<NameRow>(
    'SELECT * FROM names WHERE entity_id = ? AND locale = ? ORDER BY is_primary DESC, id',
    entityId,
    lang,
  );
  return candidates.find((c) => sameSeries(entityId, c.id, verbatimId));
}

/** 4段目：導出転写。発火条件を満たさなければ undefined（＝逐語へ劣化）。 */
function derive(base: NameRow, _lang: Lang): { text: string; lang: string } | undefined {
  if (base.origin !== 'original') return undefined; // adapted は二次転写禁止
  // 自足的文字体系（ハングル・キリル等）は name_text 自体が導出入力。現データに該当言語はない。
  // ja（漢字かな交じり）は reading を入力に取る。reading が NULL なら発火せず劣化。
  if (base.lang === 'ja' || base.lang.startsWith('ja-')) {
    if (base.reading == null) return undefined; // 発火せず劣化（設計どおり）
    // reading があるケースの転写細則（修正ヘボン式・語順等）はフェーズ2残課題で未確定のため、
    // 現時点では導出を発火させず劣化に倒す（粗悪な代用を出さない）。データ投入で reading が
    // 現れた時点で細則を確定して差し込む。
    return undefined;
  }
  return undefined;
}

/** 当時名義の導出：MVの日付（atDate）に有効な名義行。期間指定が無ければ primary。 */
function nameAtDate(entityId: number, atDate: string | null): NameRow | undefined {
  const rows = namesOf(entityId).filter((n) => n.name_type !== 'legal_name');
  if (atDate) {
    const inRange = rows.find(
      (n) =>
        (n.valid_from == null || n.valid_from <= atDate) &&
        (n.valid_to == null || atDate <= n.valid_to),
    );
    if (inRange) return inRange;
  }
  return (
    rows.find((n) => n.is_primary === 1 && n.locale === 'ja') ??
    rows.find((n) => n.is_primary === 1) ??
    rows[0]
  );
}

/** 人物文脈（見出し・一覧・リンク）：人物エンティティを錨に、ページ言語の最良名を返す。 */
export function renderPerson(entityId: number, lang: Lang): Rendered {
  const est = localePrimary(entityId, lang);
  const base =
    query<NameRow>(
      'SELECT * FROM names WHERE entity_id = ? AND is_primary = 1 AND locale = ? LIMIT 1',
      entityId,
      'ja',
    )[0] ??
    query<NameRow>('SELECT * FROM names WHERE entity_id = ? AND is_primary = 1 LIMIT 1', entityId)[0] ??
    namesOf(entityId)[0];

  if (est) {
    return { main: { text: est.name_text, lang: est.lang }, degraded: false, linkId: entityId };
  }
  const derived = base ? derive(base, lang) : undefined;
  if (derived) {
    return { main: derived, degraded: false, linkId: entityId };
  }
  // 劣化：逐語（＝ja primary）＋人物リンク
  return {
    main: base ? { text: base.name_text, lang: base.lang } : { text: `melothea${entityId}`, lang },
    degraded: true,
    linkId: entityId,
  };
}

/** クレジット文脈：実クレジットが指す名義（明示 credited_name_id、無ければ日付から当時名義導出）を
 *  逐語として常に保持しつつ、ページ言語の確立形（同一系列）／導出があれば主表示に据える。 */
export function renderCredit(
  entityId: number,
  lang: Lang,
  creditedNameId: number | null,
  atDate: string | null,
): Rendered {
  const verbatimRow =
    (creditedNameId != null ? nameById(creditedNameId) : undefined) ?? nameAtDate(entityId, atDate);
  const verbatim = verbatimRow
    ? { text: verbatimRow.name_text, lang: verbatimRow.lang }
    : { text: `melothea${entityId}`, lang };

  // 2段目：同一系列の確立形のみ採用（系列不一致は採用せず次段へ）。
  const est = verbatimRow ? establishedInSeries(entityId, lang, verbatimRow.id) : undefined;
  if (est) {
    const sub = est.name_text !== verbatim.text ? verbatim : undefined;
    return { main: { text: est.name_text, lang: est.lang }, sub, degraded: false, linkId: entityId };
  }
  const derived = verbatimRow ? derive(verbatimRow, lang) : undefined;
  if (derived) {
    const sub = derived.text !== verbatim.text ? verbatim : undefined;
    return { main: derived, sub, degraded: false, linkId: entityId };
  }
  // 劣化：逐語＋人物リンク（en ページで日本語名義が出る経路）
  return { main: verbatim, degraded: true, linkId: entityId };
}
