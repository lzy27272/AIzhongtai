import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import {
  createWorkPackageItemDraft,
  duplicateWorkPackageItem,
  mapWorkPackageItem,
  moveWorkPackageItem,
  serializeWorkPackageItems,
  validateWorkPackageItems,
} from '../src/features/workPackages/configuration.ts'

const source = {
  id: 'item-1',
  item_code: 'ROOM_CHECK',
  name: '客房查房',
  description: '逐房留证',
  item_type: 'INSPECTION',
  form_version_id: 'form-1',
  required: true,
  period_type: 'DAY',
  timezone_mode: 'HOTEL',
  work_window_start: '14:30:00',
  work_window_end: '17:30:00',
  due_local_time: '17:30:00',
  grace_minutes: 10,
  weekdays: [1, 2, 3, 4, 5, 6, 7],
  holiday_policy: 'SKIP',
  waiver_allowed: false,
  target_granularity: 'ASSIGNMENT_ORG',
  review_mode: 'MANUAL',
  submission_policy: {
    attachmentRequired: true,
    attachmentCountUnlimited: true,
    maxAttachments: 200,
    maxFileSizeBytes: 20 * 1024 * 1024,
    allowedExtensions: ['jpg', 'png', 'pdf'],
    evidenceRequirements: [{
      checkpointCode: 'room_inspection', label: '查房', captureSource: 'CAMERA', mediaTypes: ['image/jpeg'],
      requiredInstances: 5, instanceField: 'roomNumbers', instanceLabel: '房号', minimumPerInstance: 1,
    }],
  },
  reminder_policy: { moments: [{ code: 'R1430', kind: 'REMINDER', localTime: '14:30', recipient: 'EXECUTORS' }] },
  report_policy: { dailyReport: true, factLabel: '客房查房', includeEvidence: true, includeExceptions: true },
  applicability_policy: { propertyType: 'HOTEL', holidayDates: ['2026-10-01'], workdayOverrides: ['2026-10-10'] },
  execution_policy: { enabled: true, delegationAllowed: true },
  standards: [{ standard_version_id: 'standard-1', usage_type: 'EXECUTION', weight: 1 }],
  responsibilities: [
    { participant_type: 'EXECUTOR', resolver_type: 'CURRENT_ASSIGNMENT', scope_strategy: 'TARGET_ORG', escalation_level: 0 },
    { participant_type: 'ACCEPTOR', resolver_type: 'DIRECT_MANAGER_ASSIGNMENT', scope_strategy: 'TARGET_ORG', escalation_level: 0 },
  ],
}

test('完整映射并回写时间、提醒、证据链、日报和启停策略', () => {
  const draft = mapWorkPackageItem(source, 0)
  assert.equal(draft.workWindowStart, '14:30')
  assert.equal(draft.evidenceRequirements[0].requiredInstances, '5')
  assert.equal(draft.reminderMoments[0].recipient, 'EXECUTORS')
  assert.equal(draft.holidayDates, '2026-10-01')
  assert.equal(draft.workdayOverrides, '2026-10-10')
  draft.enabled = false
  draft.reportIncludeExceptions = false
  const [payload] = serializeWorkPackageItems([draft])
  assert.equal(payload.executionPolicy.enabled, false)
  assert.equal(payload.executionPolicy.delegationAllowed, true)
  assert.equal(payload.submissionPolicy.evidenceRequirements[0].minimumPerInstance, 1)
  assert.equal(payload.reminderPolicy.moments[0].localTime, '14:30')
  assert.equal(payload.reportPolicy.includeExceptions, false)
  assert.deepEqual(payload.applicabilityPolicy.holidayDates, ['2026-10-01'])
  assert.deepEqual(payload.applicabilityPolicy.workdayOverrides, ['2026-10-10'])
  assert.equal(payload.applicabilityPolicy.propertyType, 'HOTEL')
  assert.equal(payload.sortOrder, 1)
})

test('所有岗位工作项支持新增、复制、排序和校验', () => {
  const first = createWorkPackageItemDraft(1, 'form-1')
  first.itemCode = 'FIRST'
  first.name = '第一项'
  const copied = duplicateWorkPackageItem([first], 0)
  assert.equal(copied.length, 2)
  assert.equal(copied[1].itemCode, 'FIRST_COPY')
  const moved = moveWorkPackageItem(copied, 1, 0)
  assert.equal(moved[0].itemCode, 'FIRST_COPY')
  assert.deepEqual(validateWorkPackageItems(moved), [])
  moved.forEach((item) => { item.enabled = false })
  assert.match(validateWorkPackageItems(moved)[0], /至少启用一个工作项/)
})

test('工作包中心挂载所有岗位通用配置器并公开完整规则入口', () => {
  const page = readFileSync(new URL('../src/ConfigurationPages.tsx', import.meta.url), 'utf8')
  const editor = readFileSync(new URL('../src/features/workPackages/WorkPackageItemEditor.tsx', import.meta.url), 'utf8')
  assert.match(page, /所有岗位通用工作模板配置/)
  assert.match(page, /<WorkPackageItemEditor/)
  for (const label of ['新增工作项', '提醒与督办', '证据链规则', '完成要求与日报', '业务数量不限', '节假日日期', '调休工作日']) assert.match(editor, new RegExp(label))
})
