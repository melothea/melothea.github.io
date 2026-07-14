// 名義表示の4段カスケード。ビルド時導出（導出値はDBに書き込まない）。
//   1. 逐語（クレジット文脈では常に保持・表示）
//   2. ページ言語localeの確立形（entity_id + locale + is_primary による直接参照）
//   3. 言語別フォールバック（現データでは未発火）
//   4. 導出転写（origin='original' かつ reading 等の入力があるとき。無ければ逐語へ劣化）

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

/** 人物文脈の2段目：ページ言語localeの primary。 */
function localePrimary(entityId: number, lang: Lang): NameRow | undefined {
  return query<NameRow>(
    'SELECT * FROM names WHERE entity_id = ? AND locale = ? AND is_primary = 1 ORDER BY id LIMIT 1',
    entityId,
    lang,
  )[0];
}

/** 4段目：導出転写。発火条件を満たさなければ undefined（＝逐語へ劣化）。 */
function derive(base: NameRow, _lang: Lang): { text: string; lang: string } | undefined {
  if (base.origin !== 'original') return undefined; // adapted は二次転写禁止
  // 自足的文字体系（ハングル・キリル等）は name_text を導出入力に取る。
  // ja（漢字かな交じり）は reading を入力に取る。reading が NULL なら発火せず劣化。
  if (base.lang === 'ja' || base.lang.startsWith('ja-')) {
    if (base.reading == null) return undefined; // 発火せず劣化
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

  // 2段目：ページ言語localeの確立形を entity_id + locale + is_primary で直接参照。
  const est = localePrimary(entityId, lang);
  if (est) {
    const sub = est.name_text !== verbatim.text ? verbatim : undefined;
    return { main: { text: est.name_text, lang: est.lang }, sub, degraded: false, linkId: entityId };
  }
  const derived = verbatimRow ? derive(verbatimRow, lang) : undefined;
  if (derived) {
    const sub = derived.text !== verbatim.text ? verbatim : undefined;
    return { main: derived, sub, degraded: false, linkId: entityId };
  }
  // 劣化：逐語＋人物リンク
  return { main: verbatim, degraded: true, linkId: entityId };
}
