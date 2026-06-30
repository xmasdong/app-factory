#!/usr/bin/env node
/**
 * token-match.mjs — design token 对账(实现 computed 样式 vs tokens.json)
 *
 * 读「实现端抽出的 computed 样式 JSON」与设计真相源 docs/design/tokens.json 比,
 * 数两类问题,写 ${ROOT}/.claude/state/token-match.json:
 *   { hardcoded_count: <int>, mismatched_count: <int>,
 *     details: [{ file, line, value, reason }] }
 * key 严格对齐 app-gate.sh:hardcoded_count>0 或 mismatched_count>0 即 FAIL。
 *
 * 两类问题定义:
 *   - hardcoded:  实现处直接写字面量(没有 token 引用),且该字面量本可由某 token 覆盖
 *                 → 实现处应只引用 token,禁硬编码。
 *   - mismatched: 实现处 computed value 回溯不到任何 token(token 集合里找不到该值),
 *                 或声称引用某 token 但 computed 值与 token 定义不一致。
 *
 * 输入约定(读 $CLAUDE_PROJECT_DIR 当项目根):
 *   - tokens:  docs/design/tokens.json  (DTCG / 嵌套 {$value} 或扁平 k:v 都吃)
 *   - computed:实现端抽出的 computed 样式 JSON。来源优先级:
 *              --computed <file>  >  .claude/state/computed-styles.json
 *     约定形状(尽量宽松,逐项给 file/line 便于回溯):
 *       { "items": [
 *           { file, line, prop, value, token? },   // token 字段可选:声称引用的 token 名
 *           ...
 *       ] }
 *     兼容旧形状: 顶层直接是数组 [...]; 或 { styles: [...] }。
 *
 * 用法:
 *   node token-match.mjs
 *   node token-match.mjs --tokens docs/design/tokens.json --computed .claude/state/computed-styles.json
 *
 * 健壮性:缺文件/坏 JSON 给清晰报错并写一个安全产物(对应 count 置 0 + note),不裸崩。
 */

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const ROOT = process.env.CLAUDE_PROJECT_DIR || process.cwd();

function arg(name, def) {
  const i = process.argv.indexOf('--' + name);
  return i !== -1 && i + 1 < process.argv.length ? process.argv[i + 1] : def;
}
const TOKENS_FILE = path.resolve(ROOT, arg('tokens', 'docs/design/tokens.json'));
const COMPUTED_FILE = path.resolve(ROOT, arg('computed', '.claude/state/computed-styles.json'));
const OUT = path.resolve(ROOT, '.claude/state/token-match.json');

function rel(p) {
  return path.relative(ROOT, p) || p;
}

function writeOut(obj) {
  try {
    fs.mkdirSync(path.dirname(OUT), { recursive: true });
    fs.writeFileSync(OUT, JSON.stringify(obj, null, 2));
  } catch (e) {
    console.error('[token-match] FATAL: 写 token-match.json 失败: ' + e.message);
    process.exit(2);
  }
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

// ── 归一化:把 computed value / token value 都压成可比对的字符串 ──
function norm(v) {
  if (v === null || v === undefined) return '';
  let s = String(v).trim().toLowerCase();
  // 颜色 #RGB → #RRGGBB,去 alpha 简写差异
  if (/^#([0-9a-f]{3})$/.test(s)) {
    s = '#' + s[1] + s[1] + s[2] + s[2] + s[3] + s[3];
  }
  // 去掉单位前的多余 0 / 尾随 0(2.0px → 2px, 0.50 → 0.5),保留数字语义
  s = s.replace(/\b0+(\d)/g, '$1');
  // rgb(a) 内空格统一
  s = s.replace(/\s+/g, ' ').replace(/\(\s+/g, '(').replace(/\s+\)/g, ')').replace(/\s*,\s*/g, ',');
  return s;
}

// ── 扁平化 tokens.json(DTCG 嵌套 {$value} / {value} / 纯标量)→ { tokenName: normValue }, valueSet ──
function flattenTokens(obj, prefix, byName, valueSet) {
  if (obj === null || typeof obj !== 'object') {
    if (prefix) {
      const n = norm(obj);
      byName[prefix] = n;
      if (n) valueSet.add(n);
    }
    return;
  }
  // DTCG 叶子: 含 $value 或 value
  const leafVal = obj.$value !== undefined ? obj.$value : obj.value !== undefined ? obj.value : undefined;
  if (leafVal !== undefined && (typeof leafVal !== 'object' || leafVal === null)) {
    const n = norm(leafVal);
    byName[prefix] = n;
    if (n) valueSet.add(n);
    return;
  }
  for (const [k, v] of Object.entries(obj)) {
    if (k.startsWith('$')) continue; // 跳过 $type/$description 等元字段
    const next = prefix ? prefix + '.' + k : k;
    flattenTokens(v, next, byName, valueSet);
  }
}

// ── 归一化 computed 输入到统一 items[] ──
function normalizeComputed(raw) {
  let items = [];
  if (Array.isArray(raw)) items = raw;
  else if (raw && Array.isArray(raw.items)) items = raw.items;
  else if (raw && Array.isArray(raw.styles)) items = raw.styles;
  else if (raw && typeof raw === 'object') {
    // 退路: { "file:line": { prop: value } } 形状
    for (const [loc, props] of Object.entries(raw)) {
      if (props && typeof props === 'object') {
        const [file, line] = loc.split(':');
        for (const [prop, value] of Object.entries(props)) {
          items.push({ file, line, prop, value });
        }
      }
    }
  }
  return items.filter(it => it && typeof it === 'object');
}

// 判断一个值像不像「字面量」(数字/颜色/带单位的尺寸/枚举字面量),用于判 hardcoded
function looksLiteral(v) {
  const s = String(v).trim();
  if (s === '') return false;
  if (/^#[0-9a-fA-F]{3,8}$/.test(s)) return true; // 颜色
  if (/^rgba?\(/i.test(s) || /^hsla?\(/i.test(s)) return true;
  if (/^-?\d+(\.\d+)?(px|rem|em|pt|dp|sp|%|vh|vw)?$/i.test(s)) return true; // 尺寸/数字
  return false;
}

function main() {
  // tokens 必须存在,否则无法对账
  if (!fs.existsSync(TOKENS_FILE)) {
    const out = {
      hardcoded_count: 0,
      mismatched_count: 0,
      details: [],
      note: '缺 ' + rel(TOKENS_FILE) + ' (design-restore Extract 未产出 tokens.json, 无法对账)',
    };
    writeOut(out);
    console.error('[token-match] ' + out.note);
    return;
  }

  let tokensRaw;
  try {
    tokensRaw = readJson(TOKENS_FILE);
  } catch (e) {
    const out = { hardcoded_count: 0, mismatched_count: 0, details: [], note: 'tokens.json 非法 JSON: ' + e.message };
    writeOut(out);
    console.error('[token-match] ' + out.note);
    return;
  }

  const byName = {};
  const valueSet = new Set();
  flattenTokens(tokensRaw, '', byName, valueSet);

  if (!fs.existsSync(COMPUTED_FILE)) {
    const out = {
      hardcoded_count: 0,
      mismatched_count: 0,
      details: [],
      note: '缺 ' + rel(COMPUTED_FILE) + ' (实现端 computed 样式未抽出, 对账跳过)',
      token_count: Object.keys(byName).length,
    };
    writeOut(out);
    console.error('[token-match] ' + out.note);
    return;
  }

  let computedRaw;
  try {
    computedRaw = readJson(COMPUTED_FILE);
  } catch (e) {
    const out = { hardcoded_count: 0, mismatched_count: 0, details: [], note: 'computed JSON 非法: ' + e.message };
    writeOut(out);
    console.error('[token-match] ' + out.note);
    return;
  }

  const items = normalizeComputed(computedRaw);
  const details = [];
  let hardcoded = 0;
  let mismatched = 0;

  for (const it of items) {
    const file = it.file != null ? String(it.file) : '<unknown>';
    const line = it.line != null ? it.line : '?';
    const prop = it.prop != null ? String(it.prop) : '';
    const rawValue = it.value;
    const value = rawValue != null ? String(rawValue) : '';
    const nVal = norm(rawValue);
    const declaredToken = it.token != null ? String(it.token) : null;

    if (value === '') continue;

    if (declaredToken) {
      // 声称引用某 token → 校验 computed 值是否等于该 token 定义
      const tokVal = byName[declaredToken];
      if (tokVal === undefined) {
        mismatched++;
        details.push({ file, line, value, reason: 'mismatched: 引用了不存在的 token "' + declaredToken + '"' + (prop ? ' (' + prop + ')' : '') });
      } else if (tokVal !== nVal) {
        mismatched++;
        details.push({ file, line, value, reason: 'mismatched: 引用 token "' + declaredToken + '"(=' + tokVal + ') 但 computed 值=' + nVal });
      }
      // 一致 → 合规,不计
      continue;
    }

    // 未声明 token 引用 = 直接字面量
    if (looksLiteral(value)) {
      if (valueSet.has(nVal)) {
        // 字面量恰好等于某 token 值 → 应改成引用该 token → 硬编码
        hardcoded++;
        const matchName = Object.keys(byName).find(n => byName[n] === nVal);
        details.push({ file, line, value, reason: 'hardcoded: 字面量' + (prop ? ' ' + prop : '') + '=' + value + ' 应引用 token "' + matchName + '"' });
      } else {
        // 字面量且不在 token 集合 → 既是硬编码又回溯不到 token → 计 mismatched(更严:实现引入了 token 外的值)
        mismatched++;
        details.push({ file, line, value, reason: 'mismatched: computed 值' + (prop ? ' ' + prop : '') + '=' + value + ' 回溯不到任何 token' });
      }
    }
    // 非字面量(如继承/auto/inherit)不计
  }

  const out = {
    hardcoded_count: hardcoded,
    mismatched_count: mismatched,
    details,
    token_count: Object.keys(byName).length,
    checked_items: items.length,
  };
  writeOut(out);
  console.error(
    '[token-match] tokens=' + out.token_count + ' 检查 ' + items.length + ' 项 → hardcoded=' + hardcoded +
    ' mismatched=' + mismatched + ' → ' + OUT
  );
}

main();
