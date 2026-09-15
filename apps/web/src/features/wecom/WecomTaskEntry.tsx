import { useEffect, useRef, useState } from 'react'
import { apiBase } from '../../api/client'
import { product } from '../../product'
import { type WecomTaskEntry } from './entryRoute'

type Props = {
  entry: WecomTaskEntry
  onCancel: () => void
}

export function WecomTaskEntryPage({ entry, onCancel }: Props) {
  const [error, setError] = useState(entry.securityError)
  const formRef = useRef<HTMLFormElement>(null)
  const submitted = useRef(false)

  useEffect(() => {
    if (entry.securityError || !entry.code) return
    if (submitted.current || !formRef.current) return
    submitted.current = true
    try {
      formRef.current.submit()
    } catch {
      submitted.current = false
      setError('企微会话跳转失败，请返回企业微信后重新打开任务。')
    }
  }, [entry])

  return <main className="login-screen wecom-entry-screen">
    <section className="login-brand"><div className="login-logo">四</div><div><span className="eyebrow">WECOM SECURE ENTRY</span><h1>{product.name}</h1><p>正在通过企业微信确认成员身份。一次性凭证不会保存在浏览器地址、历史记录或本地存储中。</p></div></section>
    <section className="login-card wecom-entry-card" aria-live="polite">
      <header><span className="panel-kicker">企业微信安全入口</span><h2>{error ? '无法安全打开中台' : '正在验证身份'}</h2><p>{error ? '系统已停止登录和页面跳转。' : '验证成功后将直接进入对应的中台页面。'}</p></header>
      {error ? <>
        <div className="inline-error">{error}</div>
        <button className="secondary wecom-entry-action" type="button" onClick={onCancel}>返回中台登录</button>
        <small>请勿转发包含一次性凭证的链接，也不要向任何人提供企业微信验证码。</small>
      </> : <>
        <form
          ref={formRef}
          action={`${apiBase}/integrations/wecom/oauth/browser-exchange`}
          method="post"
          hidden
        >
          <input type="hidden" name="exchangeCode" value={entry.code} />
        </form>
        <div className="wecom-entry-progress"><div className="spinner" /><strong>正在建立安全会话</strong><span>请保持页面打开，无需输入中台密码。</span></div>
        <small>一次性凭证使用后立即失效；权限仍由中台组织、岗位和角色校验。</small>
      </>}
    </section>
  </main>
}
