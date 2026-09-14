import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const source = readFileSync(new URL('../src/ConfigurationPages.tsx', import.meta.url), 'utf8')

test('assignment entry is consolidated into employee edit', () => {
  assert.doesNotMatch(source, /＋ 分配任职/)
  assert.doesNotMatch(source, /setModal\('assignment'\)/)
  assert.match(source, /title=\{editingId \? '编辑员工与任职'/)
  assert.match(source, /<h3>当前任职<\/h3>/)
  assert.match(source, /<h3>新增任职<\/h3>/)
})

test('employee edit can save profile only or create a complete assignment', () => {
  assert.match(source, /const assignmentDraftStarted = Boolean/)
  assert.match(source, /saveDisabled=\{Boolean\(editingId\) && assignmentDraftInvalid\}/)
  assert.match(source, /if \(assignmentDraftStarted\) await apiRequest\(`\/org\/employees\/\$\{editingId\}\/assignments`/)
  assert.match(source, /item\.id !== editingId && item\.assignmentId/)
})
