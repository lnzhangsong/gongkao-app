#!/usr/bin/env node
// 从主仓 gongkao/data/ 镜像三份 JSON → 归一化 → 写本仓 assets/data/*.json。
// 纯 Node 脚本，不进 Flutter 依赖。可重复执行以刷新内容。
//   node scripts/sync_data.mjs            # 默认源 ../gongkao/data
//   node scripts/sync_data.mjs --src=/path/to/gongkao/data

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, '..');

const srcArg = process.argv.find((a) => a.startsWith('--src='));
const srcDir = resolve(repoRoot, srcArg ? srcArg.slice('--src='.length) : '../gongkao/data');
const outDir = join(repoRoot, 'assets', 'data');

// 源文件 → 卡片类型 / 标题字段 / 是否有 group
const SOURCES = [
  { file: 'common-sense.json', kind: '常识', titleField: 'term' },
  { file: 'idioms.json', kind: '成语', titleField: 'word' },
  { file: 'politics-hot.json', kind: '时政', titleField: 'term' },
];

function normalize(raw, { kind, titleField }) {
  if (!Array.isArray(raw)) {
    throw new Error(`期望数组，实际是 ${typeof raw}`);
  }
  return raw
    .map((it) => ({
      kind,
      group: it.group ?? null,
      title: String(it[titleField] ?? '').trim(),
      body: String(it.meaning ?? '').trim(),
      extra: it.distinction ? String(it.distinction).trim() : null,
      example: it.example ? String(it.example).trim() : null,
    }))
    .filter((c) => c.title && c.body);
}

function main() {
  mkdirSync(outDir, { recursive: true });
  let total = 0;
  for (const src of SOURCES) {
    const inPath = join(srcDir, src.file);
    const cards = normalize(JSON.parse(readFileSync(inPath, 'utf8')), src);
    const outPath = join(outDir, src.file);
    writeFileSync(outPath, JSON.stringify(cards, null, 2) + '\n', 'utf8');
    total += cards.length;
    console.log(`${src.file.padEnd(22)} ${String(cards.length).padStart(4)} 张 → assets/data/`);
  }
  console.log(`\n完成，共 ${total} 张卡片。源目录：${srcDir}`);
}

main();
