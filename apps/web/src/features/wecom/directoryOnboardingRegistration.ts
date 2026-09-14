export type DirectoryOnboardingRegistrationInput = {
  requiresAccountRegistration: boolean
  displayName: string
  mobile: string
  loginName: string
  secret: string
  secretConfirmation: string
  orgUnitId: string
}

export type DirectoryOnboardingRegistrationErrors = Partial<Record<
  'displayName' | 'mobile' | 'loginName' | 'credential' | 'passwordConfirmation' | 'assignment',
  string
>>

export function normalizeMainlandMobile(value: string) {
  const digits = value.replace(/\D/g, '')
  if (digits.length === 13 && digits.startsWith('86')) return digits.slice(2)
  if (digits.length === 15 && digits.startsWith('0086')) return digits.slice(4)
  return digits
}

export function validateDirectoryOnboardingRegistration(input: DirectoryOnboardingRegistrationInput) {
  const errors: DirectoryOnboardingRegistrationErrors = {}
  const normalizedMobile = normalizeMainlandMobile(input.mobile)

  if (!input.orgUnitId) errors.assignment = '请选择岗位；暂不确定时可选择“岗位待分配”'
  if (input.requiresAccountRegistration) {
    if (!input.displayName.trim()) errors.displayName = '请输入个人姓名'
    if (!/^1[3-9]\d{9}$/.test(normalizedMobile)) errors.mobile = '请输入正确的11位手机号'
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]{2,119}$/.test(input.loginName.trim())) {
      errors.loginName = '账号需为3至120位，只能使用字母、数字、点、下划线或短横线'
    }
    if (input.secret.length < 10 || input.secret.length > 128) errors.credential = '密码必须为10至128位'
    if (input.secret !== input.secretConfirmation) errors.passwordConfirmation = '两次输入的密码不一致'
  }

  return { valid: Object.keys(errors).length === 0, errors, normalizedMobile }
}
