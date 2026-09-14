import { existsSync } from 'node:fs'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { createRequire } from 'node:module'
import path from 'node:path'
import process from 'node:process'
import { fileURLToPath } from 'node:url'
import { requireExplicitUatFile, resolveIsolatedUatWebBase } from './isolated-uat-target.mjs'

const require = createRequire(import.meta.url)
const { chromium } = require(process.env.UAT_PLAYWRIGHT_MODULE ?? 'playwright')
const toolRoot = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(toolRoot, '..', '..')
const webBase = await resolveIsolatedUatWebBase(repoRoot)
const tokenFile = requireExplicitUatFile('UAT_TOKEN_FILE')
const outputRoot = path.resolve(process.env.UAT_OUTPUT_DIR ?? path.join(repoRoot, '.uat-runtime', 'evidence', 'all-position-work-config'))
const browserExecutable = process.env.UAT_BROWSER_EXECUTABLE
  ?? ['C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe', 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'].find(existsSync)

if (!browserExecutable || !existsSync(browserExecutable)) throw new Error('Chrome or Edge is required for browser UAT.')
const tokenDocument = JSON.parse(await readFile(tokenFile, 'utf8'))
const accessToken = tokenDocument.tokens?.ceo
if (tokenDocument.audience !== 'hotel-ai-os-api' || tokenDocument.algorithm !== 'RS256'
  || typeof accessToken !== 'string' || accessToken.length < 100) {
  throw new Error('The isolated UAT CEO token is missing or invalid.')
}

await mkdir(outputRoot, { recursive: true })
const browser = await chromium.launch({ headless: true, executablePath: browserExecutable })
const context = await browser.newContext({ viewport: { width: 1800, height: 1100 }, locale: 'zh-CN', timezoneId: 'Asia/Shanghai' })
await context.addInitScript(() => {
  window.sessionStorage.setItem('hotel-ai-os-federated-session', 'wecom')
  window.localStorage.setItem('hotel-ai-os-role:v1', 'ceo')
})
await context.route('**/api/v1/**', async (route) => {
  const request = route.request()
  if (request.method() === 'OPTIONS') {
    await route.fulfill({
      status: 204,
      headers: {
        'access-control-allow-origin': webBase,
        'access-control-allow-credentials': 'true',
        'access-control-allow-methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
        'access-control-allow-headers': request.headers()['access-control-request-headers'] ?? '*',
      },
    })
    return
  }
  let response
  try {
    response = await route.fetch({ headers: {
      ...request.headers(),
      origin: 'http://127.0.0.1:5173',
      authorization: `Bearer ${accessToken}`,
      'x-hotel-ai-authorization': `Bearer ${accessToken}`,
    } })
  } catch {
    await route.fulfill({ status: 502, contentType: 'application/json', body: '{"detail":"isolated UAT API unavailable"}' })
    return
  }
  await route.fulfill({
    response,
    headers: {
      ...response.headers(),
      'access-control-allow-origin': webBase,
      'access-control-allow-credentials': 'true',
    },
  })
})

const page = await context.newPage()
const consoleErrors = []
const pageErrors = []
const failedRequests = []
const clientErrors = []
const serverErrors = []
const steps = []
page.on('console', (message) => { if (message.type() === 'error') consoleErrors.push(message.text()) })
page.on('pageerror', (exception) => pageErrors.push(exception.message))
page.on('requestfailed', (request) => failedRequests.push({ url: request.url(), reason: request.failure()?.errorText ?? 'unknown' }))
page.on('response', (response) => {
  const detail = { url: response.url(), method: response.request().method(), status: response.status() }
  if (response.status() >= 500) serverErrors.push(detail)
  else if (response.status() >= 400) clientErrors.push(detail)
})

let passed = false
let error = null
const screenshotPath = path.join(outputRoot, 'all-position-work-config.png')
try {
  await page.goto(`${webBase}/#/work-packages`, { waitUntil: 'networkidle', timeout: 45_000 })
  await page.getByRole('heading', { name: '工作包中心' }).waitFor({ timeout: 15_000 })
  await page.locator('.package-card').first().waitFor({ state: 'visible', timeout: 20_000 })
  steps.push('CEO 进入真实工作包中心 PASS')

  await page.locator('.package-card').first().getByRole('button', { name: /查看版本与/ }).click()
  const dialog = page.getByRole('dialog')
  await dialog.getByRole('heading', { name: /版本与下发/ }).waitFor({ timeout: 20_000 })
  if (await dialog.getByRole('button', { name: '创建可编辑新版本' }).count()) {
    await dialog.getByRole('button', { name: '创建可编辑新版本' }).click()
  }
  await dialog.getByRole('heading', { name: '所有岗位通用工作模板配置' }).waitFor({ timeout: 30_000 })
  const editor = dialog.locator('.work-package-editor')
  const originalItemCount = await editor.locator('.work-item-card').count()
  if (originalItemCount < 1) throw new Error('模板没有可编辑工作项。')
  steps.push('打开全岗位通用模板编辑器 PASS')

  await editor.getByRole('button', { name: '＋ 新增工作项' }).click()
  await editor.getByLabel('开始时间', { exact: true }).fill('08:30')
  await editor.getByLabel('结束时间', { exact: true }).fill('17:30')
  await editor.getByLabel('截止时间', { exact: true }).fill('18:00')
  await editor.locator('label').filter({ hasText: '节假日策略' }).locator('select').selectOption('SKIP')
  await editor.locator('label').filter({ hasText: '节假日日期' }).locator('input').fill('2026-10-01')
  await editor.locator('label').filter({ hasText: '调休工作日' }).locator('input').fill('2026-10-10')
  steps.push('新增工作项并配置时间、星期及节假日规则 PASS')

  await editor.getByRole('button', { name: '＋ 提醒时点' }).click()
  const reminder = editor.locator('.reminder-row').last()
  await reminder.locator('label').filter({ hasText: '类型' }).locator('select').selectOption('PROGRESS')
  await reminder.getByLabel('时间', { exact: true }).fill('16:30')
  await reminder.locator('label').filter({ hasText: '接收人' }).locator('select').selectOption('DIRECT_MANAGER')
  steps.push('配置执行提醒与直属领导督办 PASS')

  await editor.getByRole('button', { name: '＋ 证据点' }).click()
  const evidence = editor.locator('.evidence-rule-card').last()
  await evidence.getByLabel('证据点编码', { exact: true }).fill('uat-proof')
  await evidence.getByLabel('显示名称', { exact: true }).fill('现场工作证据')
  await evidence.getByLabel('实例数量', { exact: true }).fill('5')
  await evidence.getByLabel('实例字段', { exact: true }).fill('roomNumbers')
  await evidence.getByLabel('实例名称', { exact: true }).fill('房号')
  await evidence.getByLabel('每个实例最低数量', { exact: true }).fill('1')
  await editor.getByLabel('业务数量不限（安全上限200）', { exact: true }).check()
  steps.push('配置图片/文档及按房号实例证据链 PASS')

  await editor.getByLabel('日报显示名称', { exact: true }).fill('全岗位配置浏览器验收')
  await editor.getByLabel('日报展示证据', { exact: true }).check()
  await editor.getByLabel('日报展示异常', { exact: true }).check()
  steps.push('配置日报自动汇总规则 PASS')

  await editor.getByRole('button', { name: '复制', exact: true }).click()
  await editor.getByLabel('生成新工作', { exact: true }).uncheck()
  await editor.getByRole('button', { name: '上移', exact: true }).click()
  const finalItemCount = await editor.locator('.work-item-card').count()
  if (finalItemCount !== originalItemCount + 2) throw new Error(`新增与复制数量异常：${originalItemCount} -> ${finalItemCount}`)
  steps.push('复制、停用及排序工作项 PASS')

  const saveResponse = page.waitForResponse((response) => response.request().method() === 'PUT'
    && /\/api\/v1\/work-packages\/[^/]+\/versions\/[^/]+$/.test(new URL(response.url()).pathname))
  await dialog.getByRole('button', { name: '保存全部草稿' }).click()
  const response = await saveResponse
  if (!response.ok()) throw new Error(`保存全部草稿失败：HTTP ${response.status()}`)
  const detailUrl = response.url().replace(/\/versions\/[^/]+$/, '')
  const savedDetail = await page.evaluate(async (url) => {
    const readResponse = await fetch(url)
    if (!readResponse.ok) throw new Error(`工作包回读失败：HTTP ${readResponse.status}`)
    return readResponse.json()
  }, detailUrl)
  const savedItems = savedDetail.latestVersion?.items ?? []
  if (savedItems.length !== finalItemCount) throw new Error(`工作项保存数量异常：${savedItems.length}/${finalItemCount}`)
  const policy = (item, camel, snake) => item[camel] ?? item[snake] ?? {}
  const configured = savedItems.find((item) => policy(item, 'reportPolicy', 'report_policy').factLabel === '全岗位配置浏览器验收')
  if (!configured) throw new Error('保存后未回读到日报、提醒和证据链配置。')
  if (policy(configured, 'reminderPolicy', 'reminder_policy').moments?.[0]?.recipient !== 'DIRECT_MANAGER') {
    throw new Error('直属领导督办配置未持久化。')
  }
  if (policy(configured, 'submissionPolicy', 'submission_policy').evidenceRequirements?.[0]?.instanceField !== 'roomNumbers') {
    throw new Error('按房号实例证据链配置未持久化。')
  }
  if (!savedItems.some((item) => policy(item, 'executionPolicy', 'execution_policy').enabled === false)) {
    throw new Error('工作项停用配置未持久化。')
  }
  steps.push('完整配置持久化并从 API 回读 PASS')

  if (consoleErrors.length || pageErrors.length || failedRequests.length || serverErrors.length) {
    throw new Error(`浏览器健康失败：console=${consoleErrors.length}, page=${pageErrors.length}, requests=${failedRequests.length}, server=${serverErrors.length}`)
  }
  passed = true
} catch (caught) {
  error = caught instanceof Error ? caught.message : String(caught)
} finally {
  await page.screenshot({ path: screenshotPath, fullPage: true }).catch(() => {})
  await context.close()
  await browser.close()
}

const report = {
  generatedAt: new Date().toISOString(), target: webBase, passed, error, steps,
  browserAutomation: 'Playwright fallback (Browser plugin unavailable)',
  screenshot: path.basename(screenshotPath), credentialsPersistedInEvidence: false,
  consoleErrors, pageErrors, failedRequests, clientErrors, serverErrors,
}
await writeFile(path.join(outputRoot, 'result.json'), `${JSON.stringify(report, null, 2)}\n`, 'utf8')
if (!passed) {
  process.stderr.write(`All-position work configuration browser UAT failed: ${error}\n`)
  process.exitCode = 1
} else {
  process.stdout.write(`All-position work configuration browser UAT PASS (${steps.length} checks).\n`)
}
