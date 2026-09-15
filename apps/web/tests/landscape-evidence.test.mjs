import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { isLandscapeDimensions } from '../src/app/imageEvidence.ts'

const appSource = readFileSync(new URL('../src/App.tsx', import.meta.url), 'utf8')
const pageSource = readFileSync(new URL('../src/P0Pages.tsx', import.meta.url), 'utf8')
const serviceSource = readFileSync(new URL('../../core-api/src/main/java/cn/sifangguan/hotelaios/workdata/AttachmentService.java', import.meta.url), 'utf8')

test('landscape dimensions require width to be strictly greater than height', () => {
  assert.equal(isLandscapeDimensions({ width: 1600, height: 900 }), true)
  assert.equal(isLandscapeDimensions({ width: 900, height: 1600 }), false)
  assert.equal(isLandscapeDimensions({ width: 1000, height: 1000 }), false)
})

test('work-record and task evidence selectors share immediate landscape validation', () => {
  assert.match(appSource, /validateLandscapeEvidence/)
  assert.match(appSource, /所有照片必须横向拍摄/)
  assert.match(appSource, /照片必须横向；支持 JPG、PNG、PDF、Word、Excel/)
  assert.match(appSource, /disabled=\{!!saving \|\| validatingAttachments\}/)
})

test('backend is authoritative and normalizes EXIF before rejecting portrait or square images', () => {
  assert.match(serviceSource, /jpegExifOrientation\(content\)/)
  assert.match(serviceSource, /normalizeImageOrientation\(sourceImage, exifOrientation, mediaType\)/)
  assert.match(serviceSource, /image\.getWidth\(\) <= image\.getHeight\(\)/)
  assert.match(serviceSource, /orientationPolicy", "LANDSCAPE"/)
})

test('team review opens with a labeled direct image gallery and bounded parallel loading', () => {
  assert.match(pageSource, /className="evidence-gallery"/)
  assert.match(pageSource, /evidenceContext\(item, expectation\)/)
  assert.match(pageSource, /Math\.min\(4, imageAttachments\.length\)/)
  assert.match(pageSource, /历史竖图会完整适配在横向画框中/)
  assert.match(pageSource, /上一张图片/)
  assert.match(pageSource, /下一张图片/)
})
