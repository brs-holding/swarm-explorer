// Drives a real browser over the last N blocks and N transactions of the
// explorer and reports any page that errors, 500s, or renders a crash marker.
//
//   node explorer-check.mjs <baseUrl> [count] [rpcUrl]
import { chromium } from 'playwright';

const BASE = process.argv[2] || 'http://127.0.0.1:14002';
const COUNT = Number(process.argv[3] || 100);
const RPC = process.argv[4] || 'http://127.0.0.1:18232/';
const CONCURRENCY = 6;

// nginx blocks ~*HeadlessChrome as a bad bot, so the check has to present the
// same user agent a real visitor would.
const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

const rpc = async (method, params = []) => {
  const r = await fetch(RPC, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }),
  });
  const { result, error } = await r.json();
  if (error) throw new Error(`${method}: ${JSON.stringify(error)}`);
  return result;
};

// Anything the app renders when a handler or template blew up.
const CRASH_MARKERS = [
  'Internal Server Error',
  'Something went wrong',
  'we can&#39;t find the internet',
  'Server Error',
];

async function checkPage(page, url, expect) {
  const consoleErrors = [];
  const onConsole = (m) => m.type() === 'error' && consoleErrors.push(m.text());
  page.on('console', onConsole);
  try {
    const resp = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
    const status = resp ? resp.status() : 0;
    const body = await page.content();
    const problems = [];
    if (status !== 200) problems.push(`HTTP ${status}`);
    for (const marker of CRASH_MARKERS) {
      if (body.includes(marker)) problems.push(`marcador de crash: "${marker}"`);
    }
    for (const [label, needle] of Object.entries(expect)) {
      if (!body.includes(needle)) problems.push(`falta ${label}`);
    }
    if (consoleErrors.length) problems.push(`console: ${consoleErrors.slice(0, 2).join(' | ')}`);
    return { url, status, problems };
  } catch (e) {
    return { url, status: 0, problems: [`excepcion: ${e.message.split('\n')[0]}`] };
  } finally {
    page.off('console', onConsole);
  }
}

async function runPool(browser, jobs) {
  const results = [];
  let next = 0;
  await Promise.all(
    Array.from({ length: CONCURRENCY }, async () => {
      const ctx = await browser.newContext({ ignoreHTTPSErrors: true, userAgent: USER_AGENT });
      const page = await ctx.newPage();
      while (true) {
        const i = next++;
        if (i >= jobs.length) break;
        const { url, expect } = jobs[i];
        const res = await checkPage(page, url, expect);
        results.push(res);
        process.stdout.write(res.problems.length ? 'x' : '.');
      }
      await ctx.close();
    })
  );
  process.stdout.write('\n');
  return results;
}

const tip = await rpc('getblockcount');
const heights = Array.from({ length: COUNT }, (_, i) => tip - i);
console.log(`tip=${tip}  base=${BASE}  revisando ${COUNT} bloques`);

// Collect the most recent COUNT transactions, walking back from the tip.
const txids = [];
for (const h of heights) {
  if (txids.length >= COUNT) break;
  const block = await rpc('getblock', [String(h), 1]);
  for (const t of block.tx || []) {
    if (txids.length < COUNT) txids.push(t);
  }
}
console.log(`recolectadas ${txids.length} transacciones`);

const browser = await chromium.launch();

console.log('\n== BLOQUES ==');
const blockJobs = heights.map((h) => ({
  url: `${BASE}/blocks/${h}`,
  expect: { 'la altura en la pagina': String(h) },
}));
const blockResults = await runPool(browser, blockJobs);

console.log('\n== TRANSACCIONES ==');
const txJobs = txids.map((t) => ({
  url: `${BASE}/transactions/${t}`,
  expect: { 'el txid en la pagina': t },
}));
const txResults = await runPool(browser, txJobs);

// The shapes that actually produced 500s in production. The last 100 blocks
// and transactions are the happy path and pass on both images, so this is the
// section that tells the two apart.
console.log('\n== CASOS BORDE (los que rompian) ==');
const EDGE = [
  ['tx con spends y outputs blindados y valueBalance 0',
   '/transactions/6f84eb33a16020bf226fd71c85556428c84a65d480e84eac2d8a6868b6beca0a'],
  ['tx que rompia unknown_tx_fees',
   '/transactions/90766e8f12a20fc09d45643af13d869e0b3729cfbf7067c9b9bf4064b1f9b7b4'],
  ['tx que rompia get_shielded_pool_label',
   '/transactions/04162164ca606752a031fa7b5524e4c265f75a1a2c69cfbdc85ab5d4a6557182'],
  ['direccion sapling',
   '/address/zs1das2v8wedfwnkugaufv7zfzlnmmjwl4dq0grhx5whuy2l2efz4janalwpkrwv9kxfy9yjxdfgfy'],
  ['busqueda de direccion sapling',
   '/search?qs=zs1das2v8wedfwnkugaufv7zfzlnmmjwl4dq0grhx5whuy2l2efz4janalwpkrwv9kxfy9yjxdfgfy'],
  ['listado de bloques con limit no numerico', '/blocks?limit=abc'],
  ['mempool (itera un assign que puede venir vacio)', '/mempool'],
  ['nodos (idem)', '/nodes'],
];
const edgeResults = [];
{
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true, userAgent: USER_AGENT });
  const page = await ctx.newPage();
  for (const [label, path] of EDGE) {
    const r = await checkPage(page, BASE + path, {});
    edgeResults.push({ ...r, label });
    console.log(`  ${r.problems.length ? 'FALLA' : '  OK '}  HTTP ${r.status}  ${label}`);
    if (r.problems.length) console.log(`            ${r.problems.join('; ')}`);
  }
  await ctx.close();
}

await browser.close();

const report = (label, results) => {
  const bad = results.filter((r) => r.problems.length);
  console.log(`\n${label}: ${results.length - bad.length}/${results.length} OK`);
  for (const r of bad.slice(0, 20)) {
    console.log(`  FALLA ${r.url}\n         ${r.problems.join('; ')}`);
  }
  if (bad.length > 20) console.log(`  ... y ${bad.length - 20} mas`);
  return bad.length;
};

const edgeBad = edgeResults.filter((r) => r.problems.length).length;
const failed = report('Bloques', blockResults) + report('Transacciones', txResults) + edgeBad;
console.log(`\nCasos borde: ${edgeResults.length - edgeBad}/${edgeResults.length} OK`);
console.log(`\nRESULTADO: ${failed === 0 ? 'todo OK' : failed + ' paginas con problemas'}`);
process.exit(failed === 0 ? 0 : 1);
