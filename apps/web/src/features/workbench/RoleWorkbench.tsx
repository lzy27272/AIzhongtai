import { useEffect, useMemo, useState } from 'react'
import {
  loadAccessibleHotels,
  loadMyWork,
  loadNotifications,
  loadOperationsDashboard,
  loadTasks,
  loadTeamWork,
} from '../../api/resources'
import { permissions as permissionCodes } from '../../app/permissions'
import type { AppNavigate } from '../../app/routeConfig'
import type { RolePresentationKey } from '../../app/rolePresentationPolicy'
import type {
  AccessibleHotel,
  ApiSource,
  OperationsHotel,
  RoleContext,
  RouteParams,
  WorkExpectation,
} from '../../domain'
import { TeamWorkDrawer } from '../../P0Pages'
import { useResource } from '../../useResource'

const completedStatuses = new Set(['SUBMITTED', 'SATISFIED', 'COMPLETED', 'APPROVED', 'WAIVED'])
const overdueStatuses = new Set(['OVERDUE', 'MISSED', 'FAILED'])
const executiveKeys = new Set<RolePresentationKey>([
  'GROUP_CHAIRMAN', 'GROUP_VICE_PRESIDENT', 'CEO', 'REGIONAL_OPERATIONS', 'PLATFORM_ADMIN',
])
const hotelManagementKeys = new Set<RolePresentationKey>(['HOTEL_MANAGER', 'ASSISTANT_MANAGER'])

type HotelRow = AccessibleHotel & Partial<OperationsHotel>
type WorkbenchStatus = 'ALL' | 'COMPLETED' | 'PENDING' | 'OVERDUE' | 'LATE_SUBMITTED'

function allows(granted: string[], permission: string) {
  return granted.includes('*') || granted.includes(permission)
}

function businessDate() {
  return new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Shanghai' }).format(new Date())
}

function formatDate(value?: string) {
  if (!value) return '—'
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return value
  return new Intl.DateTimeFormat('zh-CN', {
    month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit',
  }).format(date)
}

function isDaily(item: WorkExpectation) {
  return item.periodType === 'DAY' || item.periodKey?.startsWith('DAY:') === true
}

export function isLateSubmitted(item: WorkExpectation) {
  const submittedAt = item.latestSubmittedAt ?? item.records?.[0]?.submittedAt
  if (!submittedAt || !item.dueAt) return false
  const submitted = new Date(submittedAt).getTime()
  const due = new Date(item.dueAt).getTime()
  return Number.isFinite(submitted) && Number.isFinite(due) && submitted > due
}

function currentScopeWork(items: WorkExpectation[]) {
  const today = businessDate()
  return items.filter((item) => !isDaily(item) || item.businessDate === today || isLateSubmitted(item))
}

function hotelIdFor(item: WorkExpectation) {
  return item.hotelOrgUnitId ?? item.orgUnitId
}

function statusFor(item: WorkExpectation): Exclude<WorkbenchStatus, 'ALL'> {
  if (isLateSubmitted(item)) return 'LATE_SUBMITTED'
  if (overdueStatuses.has(item.status)) return 'OVERDUE'
  if (completedStatuses.has(item.status)) return 'COMPLETED'
  return 'PENDING'
}

function countByStatus(items: WorkExpectation[]) {
  return items.reduce((counts, item) => {
    counts[statusFor(item)] += 1
    return counts
  }, { COMPLETED: 0, PENDING: 0, OVERDUE: 0, LATE_SUBMITTED: 0 })
}

function statusLabel(status: WorkbenchStatus) {
  return ({ ALL: '全部工作', COMPLETED: '已完成', PENDING: '待提交', OVERDUE: '仍未提交', LATE_SUBMITTED: '已补交' })[status]
}

function EmptyState({ title, description }: { title: string; description: string }) {
  return <div className="workbench-empty"><span>◇</span><strong>{title}</strong><small>{description}</small></div>
}

function WorkRows({ items, onSelect }: { items: WorkExpectation[]; onSelect: (item: WorkExpectation) => void }) {
  if (!items.length) return <EmptyState title="当前分类暂无工作" description="切换其他状态或门店查看；系统不会用演示记录填充真实空结果。" />
  return <div className="workbench-record-list">
    {items.map((item) => <button type="button" key={item.id} onClick={() => onSelect(item)}>
      <span className={`workbench-record-state ${statusFor(item).toLowerCase()}`} />
      <span className="workbench-record-main"><strong>{item.title}</strong><small>{item.targetOrgName} · {item.assigneeName}{item.positionName ? ` · ${item.positionName}` : ''}</small></span>
      <span className="workbench-record-time"><small>截止 {formatDate(item.dueAt)}</small>{isLateSubmitted(item) && <em>补交 {formatDate(item.latestSubmittedAt ?? item.records?.[0]?.submittedAt)}</em>}</span>
      <b>{statusLabel(statusFor(item))} ›</b>
    </button>)}
  </div>
}

function SummaryTable({ title, subtitle, rows }: { title: string; subtitle: string; rows: Array<{ name: string; total: number; completed: number; pending: number; overdue: number }> }) {
  return <section className="workbench-summary-table">
    <header><div><span className="panel-kicker">SCOPE SUMMARY</span><h3>{title}</h3></div><small>{subtitle}</small></header>
    {!rows.length ? <p className="muted">当前范围暂无可统计记录。</p> : <div>
      <div className="workbench-summary-row head"><span>范围</span><span>工作</span><span>完成</span><span>待提交</span><span>逾期</span></div>
      {rows.map((row) => <div className="workbench-summary-row" key={row.name}><strong>{row.name}</strong><span>{row.total}</span><span>{row.completed}</span><span>{row.pending}</span><span className={row.overdue ? 'danger-text' : ''}>{row.overdue}</span></div>)}
    </div>}
  </section>
}

function aggregate(items: WorkExpectation[], key: (item: WorkExpectation) => string) {
  const groups = new Map<string, WorkExpectation[]>()
  items.forEach((item) => {
    const name = key(item)
    groups.set(name, [...(groups.get(name) ?? []), item])
  })
  return [...groups.entries()].map(([name, scoped]) => {
    const counts = countByStatus(scoped)
    return { name, total: scoped.length, completed: counts.COMPLETED, pending: counts.PENDING, overdue: counts.OVERDUE + counts.LATE_SUBMITTED }
  }).sort((left, right) => right.overdue - left.overdue || right.total - left.total)
}

export function RoleWorkbench({
  identity,
  permissions,
  presentationKey,
  executiveTasksEnabled,
  routeParams = {},
  go,
}: {
  identity: RoleContext
  permissions: string[]
  presentationKey: RolePresentationKey
  executiveTasksEnabled: boolean
  routeParams?: RouteParams
  go: AppNavigate
}) {
  const hasAssignment = Boolean(identity.businessActorAssignmentId)
  const canReadTeam = allows(permissions, permissionCodes.workRecord.readTeam) || allows(permissions, 'work-record.review')
  const canReadOwn = hasAssignment && (allows(permissions, 'work-record.read') || allows(permissions, 'work-record.submit') || allows(permissions, 'work.submit'))
  const canReadTasks = allows(permissions, 'task.read') || allows(permissions, 'task.act') || allows(permissions, 'task.review') || allows(permissions, permissionCodes.executiveTask.read)
  const canDispatch = allows(permissions, 'task.create') || allows(permissions, 'task.dispatch') || (executiveTasksEnabled && allows(permissions, permissionCodes.executiveTask.assign))
  const canReadNotices = allows(permissions, 'notification.read')
  const canReadOperations = allows(permissions, 'dashboard.operations')
  const canReadHotels = allows(permissions, 'dashboard.hotel')
  const canReadReports = allows(permissions, permissionCodes.dailyReport.readOwn) || allows(permissions, permissionCodes.dailyReport.readTeam)
  const canReadDailyOperations = allows(permissions, permissionCodes.dailyOperations.readHotel) || allows(permissions, permissionCodes.dailyOperations.readCrossHotel)
  const canReadKpi = allows(permissions, permissionCodes.kpi.scorecardReadOwn) || allows(permissions, permissionCodes.kpi.scorecardReadTeam) || allows(permissions, permissionCodes.kpi.scorecardReadAll) || allows(permissions, permissionCodes.kpi.templateRead)
  const executive = executiveKeys.has(presentationKey)
  const work = useResource(`${identity.key}:role-workbench-work:${canReadTeam}:${canReadOwn}`, () => canReadTeam
    ? loadTeamWork(identity)
    : canReadOwn ? loadMyWork(identity) : Promise.resolve({ data: [], source: 'api' as const }), [], 30_000)
  const tasks = useResource(`${identity.key}:role-workbench-tasks:${canReadTasks}`, () => canReadTasks && presentationKey !== 'GROUP_CHAIRMAN'
    ? loadTasks(identity, { view: hasAssignment ? 'mine' : 'team' })
    : Promise.resolve({ data: [], source: 'api' as const }), [], 30_000)
  const notices = useResource(`${identity.key}:role-workbench-notices:${canReadNotices}`, () => canReadNotices
    ? loadNotifications(identity)
    : Promise.resolve({ data: [], source: 'api' as const }), [], 30_000)
  const hotelDirectory = useResource(`${identity.key}:role-workbench-hotels:${canReadOperations}:${canReadHotels}`, async () => {
    if (canReadOperations) {
      const result = await loadOperationsDashboard(identity)
      return { data: result.data.hotels as HotelRow[], source: result.source }
    }
    if (canReadHotels) {
      const result = await loadAccessibleHotels(identity)
      return { data: result.data.hotels as HotelRow[], source: result.source }
    }
    return { data: [], source: 'api' as const }
  }, [], 60_000)
  const [selected, setSelected] = useState<WorkExpectation>()
  const scopedWork = useMemo(() => currentScopeWork(work.data), [work.data])
  const derivedHotels = useMemo(() => {
    const result = new Map<string, HotelRow>()
    scopedWork.forEach((item) => {
      const id = hotelIdFor(item)
      if (id) result.set(id, { id, name: item.hotelName ?? item.targetOrgName })
    })
    return [...result.values()]
  }, [scopedWork])
  const hotels = useMemo(() => {
    const rows = new Map<string, HotelRow>()
    hotelDirectory.data.forEach((hotel) => rows.set(hotel.id, hotel))
    derivedHotels.forEach((hotel) => { if (!rows.has(hotel.id)) rows.set(hotel.id, hotel) })
    return [...rows.values()].sort((left, right) => left.name.localeCompare(right.name, 'zh-CN'))
  }, [derivedHotels, hotelDirectory.data])
  const selectedHotel = hotels.find((hotel) => hotel.id === routeParams.hotelId)
    ?? (hotelManagementKeys.has(presentationKey) ? hotels[0] : undefined)
  const selectedHotelItems = useMemo(() => selectedHotel
    ? scopedWork.filter((item) => hotelIdFor(item) === selectedHotel.id)
    : scopedWork, [scopedWork, selectedHotel])
  const requestedStatus = (routeParams.status || 'ALL').toUpperCase() as WorkbenchStatus
  const statusFilter: WorkbenchStatus = ['ALL', 'COMPLETED', 'PENDING', 'OVERDUE', 'LATE_SUBMITTED'].includes(requestedStatus) ? requestedStatus : 'ALL'
  const filteredWork = selectedHotelItems.filter((item) => statusFilter === 'ALL' || statusFor(item) === statusFilter)
    .sort((left, right) => (right.latestSubmittedAt ?? right.dueAt ?? right.businessDate).localeCompare(left.latestSubmittedAt ?? left.dueAt ?? left.businessDate))
  const allCounts = countByStatus(scopedWork)
  const hotelCounts = countByStatus(selectedHotelItems)
  const unreadNotices = notices.data.filter((notice) => !notice.readAt)
  const activeTasks = tasks.data.filter((task) => !['COMPLETED', 'CANCELLED'].includes(task.status))
  const source: ApiSource = [work.source, tasks.source, notices.source, hotelDirectory.source].includes('demo') ? 'demo' : 'api'
  const loading = work.loading || (executive && hotelDirectory.loading)
  const error = work.error
  const departmentRows = aggregate(selectedHotelItems, (item) => item.targetOrgName || '未归属部门')
  const employeeRows = aggregate(selectedHotelItems, (item) => `${item.assigneeName}${item.positionName ? ` · ${item.positionName}` : ''}`)

  useEffect(() => {
    if (!routeParams.expectationId) return
    const linked = scopedWork.find((item) => item.id === routeParams.expectationId)
    if (linked) setSelected(linked)
  }, [routeParams.expectationId, scopedWork])

  const openHotelStatus = (hotelId: string, status: WorkbenchStatus = 'ALL') => go('workbench', { hotelId, status })
  const openTaskCreate = () => go('tasks', { view: hasAssignment ? 'mine' : 'team', create: 'true' })

  return <section className="role-workbench">
    <section className="role-workbench-hero">
      <div><span className="eyebrow">当前岗位工作</span><h1>{identity.label}工作台</h1><p>{identity.focus}</p></div>
      <div className="role-workbench-actions">
        {canDispatch && <button type="button" className="primary" onClick={openTaskCreate}>＋ 工作下达</button>}
        {canReadNotices && <button type="button" className="secondary" onClick={() => go('notifications')}>消息提醒{unreadNotices.length ? ` ${unreadNotices.length}` : ''}</button>}
        <span className={`source-flag ${source}`}>{source === 'demo' ? '演示回退' : '实时 API'}</span>
      </div>
    </section>

    {loading && <div className="state-card"><div className="spinner" /><strong>正在汇总当前岗位工作台</strong><span>门店、部门、人员与工作状态正在统一读取</span></div>}
    {error && <div className="state-card error-state"><b>!</b><strong>工作台读取失败</strong><span>{error}</span><button className="secondary" onClick={() => void work.reload()}>重新加载</button></div>}
    {!loading && !error && <>
      <section className="workbench-metrics">
        <button type="button" onClick={() => selectedHotel ? openHotelStatus(selectedHotel.id, 'PENDING') : undefined}><span>待</span><small>待提交</small><strong>{selectedHotel ? hotelCounts.PENDING : allCounts.PENDING}</strong><em>仍需员工完成</em></button>
        <button type="button" onClick={() => selectedHotel ? openHotelStatus(selectedHotel.id, 'COMPLETED') : undefined}><span>完</span><small>已完成</small><strong>{selectedHotel ? hotelCounts.COMPLETED : allCounts.COMPLETED}</strong><em>已提交或已达标</em></button>
        <button type="button" className="danger" onClick={() => selectedHotel ? openHotelStatus(selectedHotel.id, 'OVERDUE') : undefined}><span>逾</span><small>当前逾期</small><strong>{selectedHotel ? hotelCounts.OVERDUE : allCounts.OVERDUE}</strong><em>尚未完成提交</em></button>
        <button type="button" className="warning" onClick={() => selectedHotel ? openHotelStatus(selectedHotel.id, 'LATE_SUBMITTED') : undefined}><span>补</span><small>逾期后补交</small><strong>{selectedHotel ? hotelCounts.LATE_SUBMITTED : allCounts.LATE_SUBMITTED}</strong><em>保留完整证据链</em></button>
      </section>

      {executive && !selectedHotel && <section className="workbench-portfolio panel">
        <header><div><span className="panel-kicker">HOTEL PORTFOLIO</span><h2>负责门店</h2><p>点击门店，查看部门、人员和每一项工作的完成状态。</p></div><strong>{hotels.length} 家</strong></header>
        {!hotels.length ? <EmptyState title="当前未解析到负责门店" description="请检查当前任职的组织数据范围；集团总部本身不会被误算为门店。" /> : <div className="workbench-hotel-table">
          <div className="workbench-hotel-row head"><span>门店</span><span>工作总数</span><span>已完成</span><span>待提交</span><span>当前逾期</span><span>已补交</span><span>进入</span></div>
          {hotels.map((hotel) => {
            const hotelItems = scopedWork.filter((item) => hotelIdFor(item) === hotel.id)
            const counts = countByStatus(hotelItems)
            return <div className="workbench-hotel-row" key={hotel.id}>
              <span><strong>{hotel.name}</strong><small>{hotel.city || '授权门店'}{hotel.roomCount ? ` · ${hotel.roomCount} 间` : ''}</small></span>
              <span>{hotelItems.length}</span><span>{counts.COMPLETED}</span><span>{counts.PENDING}</span>
              <button type="button" className={counts.OVERDUE ? 'danger-text' : ''} onClick={() => openHotelStatus(hotel.id, 'OVERDUE')}>{counts.OVERDUE}</button>
              <button type="button" className={counts.LATE_SUBMITTED ? 'warning-text' : ''} onClick={() => openHotelStatus(hotel.id, 'LATE_SUBMITTED')}>{counts.LATE_SUBMITTED}</button>
              <button type="button" className="link-button" onClick={() => openHotelStatus(hotel.id)}>查看门店 ›</button>
            </div>
          })}
        </div>}
      </section>}

      {selectedHotel && <section className="workbench-hotel-detail panel">
        <header className="workbench-detail-heading"><div>{executive && <button type="button" className="workbench-back" onClick={() => go('workbench')}>← 返回全部门店</button>}<span className="panel-kicker">HOTEL WORKBENCH</span><h2>{selectedHotel.name}工作台</h2><p>本门店工作、部门和员工执行情况统一收口。</p></div><div className="workbench-entry-actions">
          {canReadTeam && <button type="button" onClick={() => go('team-work', { hotelId: selectedHotel.id })}>团队工作</button>}
          {canReadReports && <button type="button" onClick={() => go('daily-reports-team', { hotelId: selectedHotel.id })}>日报</button>}
          {canReadDailyOperations && <button type="button" onClick={() => go('daily-operations', { hotelId: selectedHotel.id })}>日运营</button>}
          {canReadKpi && <button type="button" onClick={() => go('kpi-center', { hotelId: selectedHotel.id })}>KPI</button>}
        </div></header>
        <div className="workbench-status-tabs">
          {(['ALL', 'COMPLETED', 'PENDING'] as WorkbenchStatus[]).map((status) => <button type="button" className={statusFilter === status ? 'active' : ''} key={status} onClick={() => openHotelStatus(selectedHotel.id, status)}>{statusLabel(status)} <b>{status === 'ALL' ? selectedHotelItems.length : hotelCounts[status]}</b></button>)}
          <button type="button" className={['OVERDUE', 'LATE_SUBMITTED'].includes(statusFilter) ? 'active danger' : 'danger'} onClick={() => openHotelStatus(selectedHotel.id, 'OVERDUE')}>已逾期 <b>{hotelCounts.OVERDUE + hotelCounts.LATE_SUBMITTED}</b></button>
        </div>
        {['OVERDUE', 'LATE_SUBMITTED'].includes(statusFilter) && <div className="workbench-overdue-tabs"><button type="button" className={statusFilter === 'OVERDUE' ? 'active' : ''} onClick={() => openHotelStatus(selectedHotel.id, 'OVERDUE')}>仍未提交 {hotelCounts.OVERDUE}</button><button type="button" className={statusFilter === 'LATE_SUBMITTED' ? 'active' : ''} onClick={() => openHotelStatus(selectedHotel.id, 'LATE_SUBMITTED')}>已补交 {hotelCounts.LATE_SUBMITTED}</button></div>}
        <WorkRows items={filteredWork} onSelect={setSelected} />
        <div className="workbench-scope-grid">
          <SummaryTable title="部门统计" subtitle="本门店各部门工作完成情况" rows={departmentRows} />
          <SummaryTable title="部门员工统计" subtitle="管理层查看本部门及下级员工" rows={employeeRows} />
        </div>
      </section>}

      {!executive && !selectedHotel && <section className="workbench-personal-grid">
        <article className="panel"><header><div><span className="panel-kicker">TODAY WORK</span><h2>{canReadTeam ? '部门岗位工作' : '今日岗位工作'}</h2></div><button className="link-button" onClick={() => go(canReadTeam ? 'team-work' : 'my-work')}>查看全部</button></header><WorkRows items={scopedWork.slice(0, 8)} onSelect={setSelected} /></article>
        <aside>
          {canReadTasks && <article className="panel workbench-compact-panel"><header><h2>任务进度</h2><button className="link-button" onClick={() => go('tasks')}>查看</button></header><strong>{activeTasks.length}</strong><span>项执行中任务</span></article>}
          {canReadNotices && <article className="panel workbench-compact-panel"><header><h2>消息提醒</h2><button className="link-button" onClick={() => go('notifications')}>查看</button></header><strong>{unreadNotices.length}</strong><span>条未读消息</span></article>}
        </aside>
      </section>}
      {!executive && !selectedHotel && canReadTeam && <div className="workbench-scope-grid workbench-team-summaries">
        <SummaryTable title="部门统计" subtitle="当前管理范围内的部门工作" rows={departmentRows} />
        <SummaryTable title="部门员工统计" subtitle="当前部门及下级员工执行情况" rows={employeeRows} />
      </div>}
    </>}
    {selected && <TeamWorkDrawer initial={selected} identity={identity} permissions={permissions} go={go} onClose={() => setSelected(undefined)} onChanged={work.reload} />}
  </section>
}
