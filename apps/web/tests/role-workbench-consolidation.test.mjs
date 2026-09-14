import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const app = readFileSync(new URL('../src/App.tsx', import.meta.url), 'utf8')
const workbench = readFileSync(new URL('../src/features/workbench/RoleWorkbench.tsx', import.meta.url), 'utf8')
const mobile = readFileSync(new URL('../src/app/rolePresentationPolicy.ts', import.meta.url), 'utf8')
const workPackageService = readFileSync(new URL('../../core-api/src/main/java/cn/sifangguan/hotelaios/workpackage/WorkPackageService.java', import.meta.url), 'utf8')
const workDataService = readFileSync(new URL('../../core-api/src/main/java/cn/sifangguan/hotelaios/workdata/WorkDataService.java', import.meta.url), 'utf8')
const attachmentService = readFileSync(new URL('../../core-api/src/main/java/cn/sifangguan/hotelaios/workdata/AttachmentService.java', import.meta.url), 'utf8')

test('cockpit, task and notification entries are consolidated into the role workbench', () => {
  assert.match(app, /\['hotel-dashboard', 'operations-dashboard', 'tasks', 'notifications'\]\.includes\(item\.id\)/)
  assert.match(app, /item\.id === 'workbench' \? `\$\{activeIdentity\.label\}工作台`/)
  assert.match(workbench, /工作下达/)
  assert.match(workbench, /消息提醒/)
})

test('rules and work package routes are platform-administrator only', () => {
  assert.match(app, /\['rules', 'work-packages'\]\.includes\(item\.id\) && !isPlatformAdmin/)
  assert.match(app, /administratorRouteAllowed/)
})

test('multi-hotel workbench supports overdue to late-submitted drill-down', () => {
  assert.match(workbench, /已逾期/)
  assert.match(workbench, /仍未提交/)
  assert.match(workbench, /已补交/)
  assert.match(workbench, /submitted > due/)
  assert.match(workbench, /TeamWorkDrawer/)
  assert.match(workbench, /部门员工统计/)
})

test('executive workbench keeps the hotel portfolio and opens the first hotel detail by default', () => {
  assert.match(workbench, /\{executive && <section className="workbench-portfolio panel">/)
  assert.match(workbench, /\(executive \|\| hotelManagementKeys\.has\(presentationKey\)\) \? hotels\[0\]/)
  assert.match(workbench, /部门工作统计/)
  assert.match(workbench, /部门员工工作统计/)
  assert.match(workbench, /<h3>工作任务<\/h3>/)
  assert.match(workbench, /今日个人工作/)
  assert.match(workbench, /管理提醒/)
})

test('daily and month-to-date completion rates use the KPI on-time formula', () => {
  assert.match(workbench, /当日完成率/)
  assert.match(workbench, /截至当日月工作完成率/)
  assert.match(workbench, /当日按时完成项 ÷ 当日应完成项/)
  assert.match(workbench, /本月截至今日按时完成项 ÷ 同期应完成项/)
  assert.match(workbench, /loadWorkbenchSummary/)
  assert.match(workPackageService, /teamWorkbenchSummary/)
  assert.match(workPackageService, /onTimeCompleted \* 100\.0 \/ expected/)
  assert.match(workPackageService, /first_record\.submitted_at/)
})

test('mobile main tabs no longer expose task and notification centers', () => {
  const factory = mobile.slice(mobile.indexOf('const tabs ='), mobile.indexOf('const modules ='))
  assert.doesNotMatch(factory, /target: 'tasks'/)
  assert.doesNotMatch(factory, /target: 'notifications'/)
  assert.match(factory, /target: 'kpi-center'/)
})

test('team readers can open submitted work records and evidence within org scope', () => {
  assert.match(workPackageService, /requireAnyPermission\("work-record\.review", "work-record\.team-read"\)/)
  assert.match(workPackageService, /"work-package\.read", "work-record\.read", "work-record\.review", "work-record\.team-read"/)
  assert.match(workDataService, /requireAnyPermission\("work-record\.read", "work-record\.review", "work-record\.team-read"\)/)
  assert.match(attachmentService, /requireAnyPermission\("work-record\.read", "work-record\.review", "work-record\.team-read"\)/)
})
