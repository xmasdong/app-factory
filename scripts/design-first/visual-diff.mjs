#!/usr/bin/env node
/**
 * visual-diff.mjs — 视觉回归 diff(实现截图 vs 设计基线)
 *
 * 用 pixelmatch + pngjs 逐屏对比「实现渲染截图」与「设计基线 PNG」,
 * 算每屏 mismatch%(0-100 int),写 ${ROOT}/.claude/state/ui-diff.json:
 *   { mismatch: <所有屏最大 int>, per_screen: [{ screen, mismatch, viewport?, platform? }] }
 * key 严格对齐 app-gate.sh:gate 读 .mismatch(>8 FAIL / 3-8 WARN / ≤3 pass)。
 *
 * 输入约定(随仓库分发,各项目 clone 即用,读 $CLAUDE_PROJECT_DIR 当项目根):
 *   - 基线:  docs/design/baseline/<platform>/<viewport>/<screen>.png
 *   - 实现:  默认 .claude/state/render/<platform>/<viewport>/<screen>.png
 *            (可 --render-dir 覆盖;按基线同名 PNG 配对)
 *   - mask:  可选,忽略动态区(动画/头像/时间戳),防纯像素 diff 假阳性。
 *            来源优先级:--mask <file.json>  >  docs/design/diff-mask.json
 *            形状: { "<platform>/<viewport>/<screen>": [{x,y,w,h}, ...],
 *                    "*": [{x,y,w,h}] }   // "*" = 应用到所有屏的全局 mask
 *
 * 用法:
 *   node visual-diff.mjs
 *   node visual-diff.mjs --render-dir build/screenshots --baseline-dir docs/design/baseline \
 *        --mask docs/design/diff-mask.json --threshold 0.1
 *
 * 健壮性:缺目录/缺文件/尺寸不符/损坏 PNG 都不抛栈,记成该屏 mismatch=100 + reason,
 *        整体退出码 0(产出 JSON 永远写盘,闸门负责判 PASS/FAIL)。
 */

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const ROOT = process.env.CLAUDE_PROJECT_DIR || process.cwd();

// ── 友好加载依赖(缺包给清晰指引,不裸崩)──
let PNG, pixelmatch;
try {
  ({ PNG } = await import('pngjs'));
} catch {
  fail('缺依赖 pngjs。请在 ' + ROOT + ' 跑: npm i -D pngjs pixelmatch');
}
try {
  const m = await import('pixelmatch');
  pixelmatch = m.default || m;
} catch {
  fail('缺依赖 pixelmatch。请在 ' + ROOT + ' 跑: npm i -D pngjs pixelmatch');
}

function fail(msg) {
  console.error('[visual-diff] FATAL: ' + msg);
  process.exit(2);
}

// ── 解析参数 ──
function arg(name, def) {
  const i = process.argv.indexOf('--' + name);
  return i !== -1 && i + 1 < process.argv.length ? process.argv[i + 1] : def;
}
const BASELINE_DIR = path.resolve(ROOT, arg('baseline-dir', 'docs/design/baseline'));
const RENDER_DIR = path.resolve(ROOT, arg('render-dir', '.claude/state/render'));
const MASK_FILE = arg('mask', null);
const THRESHOLD = clampNum(parseFloat(arg('threshold', '0.1')), 0, 1, 0.1); // pixelmatch 容差
const OUT = path.resolve(ROOT, '.claude/state/ui-diff.json');

function clampNum(v, lo, hi, def) {
  if (!Number.isFinite(v)) return def;
  return Math.min(hi, Math.max(lo, v));
}

// ── mask 加载 ──
function loadMask() {
  const candidate = MASK_FILE
    ? path.resolve(ROOT, MASK_FILE)
    : path.resolve(ROOT, 'docs/design/diff-mask.json');
  if (!fs.existsSync(candidate)) {
    if (MASK_FILE) console.error('[visual-diff] WARN: mask 文件不存在: ' + candidate + ' (忽略 mask)');
    return {};
  }
  try {
    const parsed = JSON.parse(fs.readFileSync(candidate, 'utf8'));
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch (e) {
    console.error('[visual-diff] WARN: mask JSON 解析失败 (' + candidate + '): ' + e.message + ' (忽略 mask)');
    return {};
  }
}

function maskRectsFor(key, mask) {
  const rects = [];
  if (Array.isArray(mask['*'])) rects.push(...mask['*']);
  if (Array.isArray(mask[key])) rects.push(...mask[key]);
  return rects.filter(r => r && Number.isFinite(r.x) && Number.isFinite(r.y) && Number.isFinite(r.w) && Number.isFinite(r.h));
}

// 把 mask 区域在两张图上同步刷成同色 → pixelmatch 视作相同 → 等效忽略
function applyMask(png, rects) {
  for (const r of rects) {
    const x0 = Math.max(0, Math.floor(r.x));
    const y0 = Math.max(0, Math.floor(r.y));
    const x1 = Math.min(png.width, Math.floor(r.x + r.w));
    const y1 = Math.min(png.height, Math.floor(r.y + r.h));
    for (let y = y0; y < y1; y++) {
      for (let x = x0; x < x1; x++) {
        const idx = (png.width * y + x) << 2;
        png.data[idx] = 0;
        png.data[idx + 1] = 0;
        png.data[idx + 2] = 0;
        png.data[idx + 3] = 255;
      }
    }
  }
}

// ── 收集基线 PNG(递归 baseline/<platform>/<viewport>/<screen>.png)──
function walkPngs(dir) {
  const out = [];
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const e of entries) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...walkPngs(full));
    else if (e.isFile() && e.name.toLowerCase().endsWith('.png')) out.push(full);
  }
  return out;
}

function readPng(file) {
  const buf = fs.readFileSync(file);
  return PNG.sync.read(buf);
}

function safeWriteDiff(diffPng, outPath) {
  try {
    fs.mkdirSync(path.dirname(outPath), { recursive: true });
    fs.writeFileSync(outPath, PNG.sync.write(diffPng));
  } catch {
    /* 写 diff 图失败不致命 */
  }
}

// ── 主流程 ──
function main() {
  const mask = loadMask();
  const result = { mismatch: 0, per_screen: [], threshold: THRESHOLD, baseline_dir: rel(BASELINE_DIR), render_dir: rel(RENDER_DIR) };

  if (!fs.existsSync(BASELINE_DIR)) {
    // 没有基线 = 无法判定 → 写一个空但合法的产物,并标因。闸门会因 mismatch=0 误判 pass?
    // 故这里没有屏时 mismatch 置 0(无屏可比),但 per_screen 为空 + note,交闸门 baseline_exists 关把守。
    result.note = '基线目录不存在: ' + rel(BASELINE_DIR) + ' (design-restore Extract 未产出 baseline PNG)';
    writeOut(result);
    console.error('[visual-diff] ' + result.note);
    return;
  }

  const baselines = walkPngs(BASELINE_DIR);
  if (baselines.length === 0) {
    result.note = '基线目录无 PNG: ' + rel(BASELINE_DIR);
    writeOut(result);
    console.error('[visual-diff] ' + result.note);
    return;
  }

  let maxMismatch = 0;
  for (const basePath of baselines) {
    const relKey = path.relative(BASELINE_DIR, basePath).replace(/\.png$/i, ''); // <platform>/<viewport>/<screen>
    const parts = relKey.split(path.sep);
    const screen = parts[parts.length - 1] || relKey;
    const viewport = parts.length >= 2 ? parts[parts.length - 2] : undefined;
    const platform = parts.length >= 3 ? parts[parts.length - 3] : undefined;
    const renderPath = path.join(RENDER_DIR, relKey + '.png');

    const entry = { screen, mismatch: 100 };
    if (viewport) entry.viewport = viewport;
    if (platform) entry.platform = platform;

    if (!fs.existsSync(renderPath)) {
      entry.reason = '缺实现截图: ' + rel(renderPath) + ' (该屏未渲染)';
      result.per_screen.push(entry);
      maxMismatch = Math.max(maxMismatch, entry.mismatch);
      continue;
    }

    let baseImg, renderImg;
    try {
      baseImg = readPng(basePath);
    } catch (e) {
      entry.reason = '基线 PNG 损坏: ' + e.message;
      result.per_screen.push(entry);
      maxMismatch = Math.max(maxMismatch, entry.mismatch);
      continue;
    }
    try {
      renderImg = readPng(renderPath);
    } catch (e) {
      entry.reason = '实现 PNG 损坏: ' + e.message;
      result.per_screen.push(entry);
      maxMismatch = Math.max(maxMismatch, entry.mismatch);
      continue;
    }

    if (baseImg.width !== renderImg.width || baseImg.height !== renderImg.height) {
      // 尺寸不符 = 大概率 DPR 不一致(纯像素 diff 误杀头号原因)。不强行缩放,直接判最大 mismatch 并点名。
      entry.reason =
        '尺寸不符 base=' + baseImg.width + 'x' + baseImg.height +
        ' render=' + renderImg.width + 'x' + renderImg.height +
        ' (疑 DPR 不一致: 渲染须用 manifest.extraction_meta.dpr 同一 DPR)';
      entry.baseline_size = [baseImg.width, baseImg.height];
      entry.render_size = [renderImg.width, renderImg.height];
      result.per_screen.push(entry);
      maxMismatch = Math.max(maxMismatch, entry.mismatch);
      continue;
    }

    const { width, height } = baseImg;
    const rects = maskRectsFor(relKey, mask);
    if (rects.length) {
      applyMask(baseImg, rects);
      applyMask(renderImg, rects);
      entry.masked_regions = rects.length;
    }

    const diff = new PNG({ width, height });
    let diffPixels = 0;
    try {
      diffPixels = pixelmatch(baseImg.data, renderImg.data, diff.data, width, height, {
        threshold: THRESHOLD,
        includeAA: false,
      });
    } catch (e) {
      entry.reason = 'pixelmatch 失败: ' + e.message;
      result.per_screen.push(entry);
      maxMismatch = Math.max(maxMismatch, entry.mismatch);
      continue;
    }

    const total = width * height || 1;
    const ratio = diffPixels / total;
    entry.mismatch = Math.round(ratio * 100);
    entry.diff_pixels = diffPixels;
    entry.total_pixels = total;
    delete entry.reason;

    // 写 diff 可视化图到 .claude/state/diff/ 便于人工复核
    safeWriteDiff(diff, path.resolve(ROOT, '.claude/state/diff', relKey + '.png'));

    result.per_screen.push(entry);
    maxMismatch = Math.max(maxMismatch, entry.mismatch);
  }

  result.mismatch = maxMismatch;
  writeOut(result);

  console.error(
    '[visual-diff] 比对 ' + result.per_screen.length + ' 屏, 顶层 mismatch=' + result.mismatch +
    ' → ' + OUT
  );
}

function rel(p) {
  return path.relative(ROOT, p) || p;
}

function writeOut(result) {
  try {
    fs.mkdirSync(path.dirname(OUT), { recursive: true });
    fs.writeFileSync(OUT, JSON.stringify(result, null, 2));
  } catch (e) {
    fail('写 ui-diff.json 失败: ' + e.message);
  }
}

main();
