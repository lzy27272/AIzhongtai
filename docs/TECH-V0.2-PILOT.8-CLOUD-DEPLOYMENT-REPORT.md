# TECH-V0.2-PILOT.8 云端内部Pilot部署报告

| 项目 | 结果 |
|---|---|
| 产品/设计基线 | PRODUCT-V1.4 / DESIGN-1.1 / TECH-DESIGN-1.0 |
| 部署范围 | 批次A身份与V39底座、批次B董事长受限交办；不含批次C/D |
| 目标 | 腾讯云Ubuntu / `https://www.sfgzt.cn` / GitHub `lzy27272/AIzhongtai:main` |
| 状态 | DEPLOYED / HEALTHY / FEATURES OFF / FORMAL TECH-V0.2 NO-GO |
| 日期 | 2026-09-12 |

## 1. 收口与制品

- 功能提交：`e001c2ae2c58445bae553667301f0c691c2e7edf`；该提交已快进推送至GitHub `main`并作为首次成功激活的Pilot.8功能基线。
- 后端：`hotel-ai-os-core-api-0.2.0-pilot.8.jar`，首次部署SHA-256为`535937c1bb31c50c26a1b2378e46fd084bb879beb6938b65afa59b373eac02b5`。
- Web：Pilot构建的首次`index.html` SHA-256为`32f1d6574bb8484309f763697d38a9e00949c79d8bab5799131a7083c25cbd76`；公网回读哈希一致。
- 源码变更、JAR、Web压缩包及部署脚本均通过只读敏感信息扫描，0命中、0错误。
- 后端全量测试233项，0失败、0错误、3跳过；Web契约测试58/58 PASS；OpenAPI契约及Pilot生产构建PASS。

## 2. 数据与回滚保障

- 部署前执行服务器既有加密PostgreSQL备份任务，备份文件权限`0600 root:root`，密文SHA-256校验PASS。
- Flyway从V38迁移至V39；服务器健康门禁确认JAR版本39、数据库版本39、失败迁移0。
- 首次切换因systemd尚未加载既有迁移unit，在执行迁移前失败；自动回滚恢复旧Core/Web软链接，API保持UP、数据库保持V38。
- 执行`systemctl daemon-reload`并重新激活已校验候选后迁移成功；该过程证明应用软链接回滚路径有效，没有进行数据库破坏性回退。

## 3. 稳定态验证

| 检查 | 结果 |
|---|---|
| Core API / Caddy | active / active |
| 内网健康 | `UP` |
| 公网首页 | HTTP 200 |
| 服务器与公网首页哈希 | 一致 |
| Flyway JAR / DB | 39 / 39，失败迁移0 |
| 未授权`/api/v1/iam/me` | 401 |
| 未授权`/api/v1/executive-tasks` | 401 |
| 最近5分钟Core API warning | 0 |
| GitHub/云端最终版本 | 最终收口时回读并保持一致 |

Browser插件不可用，且Playwright自带Chromium未安装；遵循前端测试流程，使用机器已有Microsoft Edge与Playwright 1.62.1，不下载新浏览器。桌面1440×900和移动390×844均确认：

- URL和页面标题正确；
- 登录页有完整有意义内容，没有框架错误层；
- 页面加载的同源资源包含`TECH-V0.2-PILOT.8`；
- 登录按钮在空表单→填入→清空密码过程中按禁用→启用→禁用变化，全程没有提交凭证；
- 控制台错误/警告、页面异常及请求失败均为0；
- 截图视觉检查未见白屏、遮挡、溢出或不可读控件。

## 4. 功能边界

- 云端`core-api.env`不存在任何`GROUP_MANAGEMENT_*`变量，应用使用默认false；租户白名单为空。
- 未创建或映射真实董事长、集团总经理、集团副总经理、行政人事主管或行政人事任职。
- 区域经理继续`DEFERRED / NOT IN USE`。
- 批次C周/月计划、批次D提醒Worker和真实人员Pilot数据包尚未实现或启用。
- 本次为内部Pilot增量部署，不等于TECH-V0.2正式发行，不解除既有正式发布门禁。

## 5. 2026-09-13 企业微信一键邀请增量发布

- GitHub `main`功能提交：`7909a1468a4510e7467a08ee98f190410bdf2a9b`。
- 发布版本：`20260913-pilot8-7909a14`；后端SHA-256为`b0dc7c24b3da9353cfc912e970125d4ac57545eac60238de177b2563a6538121`，Web `index.html` SHA-256为`bebc0ea73fa3c960cd0daae9ec17648c1e2e00237708fdc8436f20f887119e9b`，公网回读一致。
- 发布门禁：Web 70项契约测试、Pilot生产构建、企微后端专项32项及后端全量242项通过（0失败、0错误、3跳过）；空库Flyway V1→V45通过。
- 云端先完成加密PostgreSQL备份，再由Flyway V44迁移至V45；Core API与Caddy均为active，JAR/数据库均为45且失败迁移为0，部署后Core API warning为0。
- 公网首页返回200，未授权`/api/v1/iam/me`返回401，公开静态资源已回读到“一键邀请”。未使用真实员工资料执行手机号注册或审批；本增量仍属于内部Pilot，不改变TECH-V0.2正式NO-GO边界。

## 6. 2026-09-14 全岗位工作模板配置增量发布

- 功能提交为`21f874c2023f6ffa0e9d89a7018703defbbcb0dc`；为保留新仓库既有初始化历史，发布树通过无文件改动的`131568a330b60bb1f570531c61b34db00b096f7f`合并提交接入`lzy27272/AIzhongtai:main`，本地默认`origin`同步迁移至该仓库。
- 云端不可变发布版本为`20260914-pilot8-131568a`。后端JAR SHA-256为`f91c8760a5ec3e444580ae0e457928e2bc5eb5546899089db1fdc92f9b699468`；Web `index.html` SHA-256为`32b89783528b61c13aeab42cd6bb52ea599a8caaa35818cfa2e4b5fa95a41e80`，公网回读哈希一致。
- 部署前生成加密PostgreSQL备份`hotel_ai_os-auto-20260914T112332+0800.dump.enc`，密文及校验文件均为`root:root:0600`，SHA-256校验通过。Flyway由V45迁移至V48，JAR/数据库版本一致，失败迁移为0。
- Core API与Caddy均为`active`，健康状态为`UP`；公网首页返回200，未授权`/api/v1/iam/me`和`/api/v1/work-packages`均返回401，部署后5分钟Core API warning/error为0。
- 公网静态资源已回读到“所有岗位通用工作模板配置”；本次5个发布制品扫描63个归档、23726个条目，敏感信息0命中、0错误。
- 本次仍为内部Pilot增量发布，不改变TECH-V0.2正式版本的`Unreleased / NO-GO`状态，也不自动启用尚未审批的功能开关或真实人员映射。

## 7. 2026-09-14 企业微信员工入职提交反馈修复

- 功能提交为`a69241f`；修复员工注册信息不合规时“提交审核”按钮被静默禁用的问题。点击提交后会明确标记姓名、手机号、账号、密码、确认密码及门店/岗位错误；校验通过后仍使用原接口和服务端权限边界。
- 云端不可变发布版本为`20260914-pilot8-a69241f`。后端JAR SHA-256为`8da50cdff2fe7b5bdce2457391d871b9aef352250ccb796db1addc43537a459c`；Web ZIP SHA-256为`3e7dfc99b4cbb6119ba2dcbad1eb27254e5c39c3fcba158773d9363acbc35306`；Web `index.html` SHA-256为`6052ef1d6080ac82f9d64b4afb3cb70a9f21fc00da84dff9e3ababe5eb53344b`，服务器与公网回读一致。
- 部署前生成加密PostgreSQL备份`hotel_ai_os-auto-20260914T121150+0800.dump.enc`；密文及SHA校验文件均为`root:root:0600`，SHA-256复核通过。无新增数据库迁移，健康门禁为Flyway JAR V48、数据库V48、失败迁移0。
- 首次执行在正式安装前的临时解压阶段发现上一批`/tmp/hotel-ai-os-release/web`残留并进入交互询问，已立即中止；旧Core/Web软链接、服务健康和候选目录均确认未变化。清理经绝对路径校验的临时子目录后重新执行，安装、迁移门禁和原子切换成功。
- 部署后Core API与Caddy均为`active`，健康状态为`UP`；公网首页返回200，未授权`/api/v1/iam/me`返回401，公开主资源已回读到“密码必须为10至128位”和“提交信息尚未完整”，启动后的warning/error/exception为0。
- 验证：Web全量77项、TypeScript和Pilot生产构建通过；移动端390×844页面闭环10项通过。5个变更文件和5个发布制品（含63个归档、23726个条目）敏感信息扫描均为0命中、0错误。
- 本次仍为内部Pilot增量发布，不改变TECH-V0.2正式版本的`Unreleased / NO-GO`状态；未使用真实员工资料执行注册或审批。

## 8. 2026-09-14 企业微信多人复用邀请与集团总部入职申请

- 功能提交为`0c7c04ad99a519e9e23cfccd678474f6cf421c8b`；员工一键邀请改为120分钟共享邀请，同一二维码可由多名员工同时扫码，每次扫码创建独立申请，员工提交不会消耗共享邀请，仅固定时间到期后失效。注册组织选项同时包含启用中的集团总部与门店。
- 集团总部入职申请在审核前允许岗位待分配；审核端只提供`GROUP_MANAGEMENT`且不含TENANT授权或不可委派权限的安全岗位，集团董事长、平台管理员等受保护岗位不能通过入职审核授予。
- 云端不可变发布版本为`20260914-pilot8-0c7c04a`。后端JAR SHA-256为`35c349c76a632f3a10551b8b22de93a1fb153a3d438a30a8b5cb96a7d46c64c8`；Web ZIP SHA-256为`304717be3bf29f6c7b14f6d7ef8c1bc3e2183e9e8585ff00cd0add0e87f2e42a`；Web `index.html` SHA-256为`a7e4ce8e71dd34677b88b665aec64442e9d09d8b31edd447ed9b39c62c0e14f7`，服务器与公网回读一致。
- 部署前生成加密PostgreSQL备份`hotel_ai_os-auto-20260914T130523+0800.dump.enc`；密文及SHA校验文件均为`root:root:0600`，SHA-256复核通过。Flyway由V48迁移至V49，JAR/数据库版本均为49，失败迁移0。
- 部署后Core API与Caddy均为`active`，健康状态为`UP`；公网首页返回200，未授权`/api/v1/iam/me`返回401，公开静态资源已回读到“同一二维码在有效期内可供多名员工分别使用”，启动后的warning/error/exception为0。
- 验证：后端全量251项（0失败、0错误、3跳过）、企微入职专项35项、Web全量79项和专项12项、TypeScript、Pilot生产构建及Flyway V1→V49通过；桌面及390×844手机真实页面闭环11项通过，控制台错误、页面异常与请求失败均为0。5个发布制品敏感信息扫描0命中、0错误。
- 未使用真实员工资料执行线上注册或审批；本次仍为内部Pilot增量发布，不改变TECH-V0.2正式版本的`Unreleased / NO-GO`状态。

## 9. 2026-09-14 企业微信工作台 callback 下载页兼容修复

- 功能提交为`aa90f09b62c282c32490c6670de14862ad46e8d0`。根因是企业微信工作台应用主页直接指向OAuth回调地址，首次打开不携带`code/state`；原401非HTML响应被iOS企业微信识别为名为`callback`的下载文件。修复后仅在两个参数同时缺失时安全启动工作台OAuth；单参数缺失、Cookie冲突和伪造状态仍关闭式拒绝。
- 云端不可变发布版本为`20260914-pilot8-aa90f09`。后端JAR SHA-256为`8a2164010e28e45c525b68e6dcd1a38781a08db9addd00704a785f9dd6e7dc5f`；Web沿用上一稳定包，ZIP SHA-256为`304717be3bf29f6c7b14f6d7ef8c1bc3e2183e9e8585ff00cd0add0e87f2e42a`，`index.html` SHA-256为`a7e4ce8e71dd34677b88b665aec64442e9d09d8b31edd447ed9b39c62c0e14f7`。
- 部署前生成并验证加密PostgreSQL备份`hotel_ai_os-auto-20260914T135543+0800.dump.enc`；Flyway JAR/数据库均为V49，失败迁移0。Core API与Caddy均为`active`，健康状态为`UP`，部署启动窗口内warning/error/exception均为0。
- 公网响应验证：无参数`/api/v1/integrations/wecom/oauth/callback`返回302并跳转企业微信OAuth，设置新的工作台校验Cookie、清除残留入职绑定Cookie、使用no-store策略，无`Content-Disposition`且响应体为空；只提供`code`的异常请求返回401且不跳转。
- Browser实页验证到达企业微信授权域名并显示“请在企业微信客户端打开链接”，未再出现callback文件下载页。外部Browser没有真实企业微信客户端登录态，因此最终账号交换与工作台落地仍需在用户企业微信客户端复验。
- 控制器专项5项、后端全量253项（0失败、0错误、3跳过）和Flyway V1→V49通过；5个发布制品扫描63个归档、23728个条目，敏感信息0命中、0错误。本次仍为内部Pilot增量发布，不改变TECH-V0.2正式版本的`Unreleased / NO-GO`状态。

## 10. 2026-09-14 企业微信多岗位账号登录恢复

- 功能提交为`0ff58b9ddc9c9ad3842a4183dbb6cb306f9997fa`。生产OAuth记录证明14:09的请求已通过状态和浏览器Cookie校验并领取供应商授权码，失败点位于身份解析；根因是绑定巡检把员工新增第二个有效任职错误视为必须暂停，与既定的一人多岗位规则冲突。
- 修复后，多岗位员工的原默认任职只要仍有效，绑定保持ACTIVE并刷新任职快照；仅因`MULTIPLE_ACTIVE_ASSIGNMENTS`被历史误暂停的绑定自动恢复。默认任职缺失或失效、人工暂停、账号/员工失效等状态继续关闭式拦截。合法工作台OAuth在身份解析失败时跳转中台HTML故障页，避免iOS企业微信再次把空401回调识别为下载文件；入职绑定流和非法状态仍返回401。
- 云端不可变发布版本为`20260914-pilot8-0ff58b9`。后端JAR SHA-256为`9ce2c1df4b6250471e52640b34bf778568bc0ac405bf1566bcc8e807f92ed08b`；Web沿用稳定包，ZIP SHA-256为`304717be3bf29f6c7b14f6d7ef8c1bc3e2183e9e8585ff00cd0add0e87f2e42a`，`index.html` SHA-256为`a7e4ce8e71dd34677b88b665aec64442e9d09d8b31edd447ed9b39c62c0e14f7`，服务器回读一致。
- 部署前生成加密PostgreSQL备份`hotel_ai_os-auto-20260914T144613+0800.dump.enc`；5个发布制品敏感信息扫描0命中、0错误。Core API与Caddy均为`active`，健康状态为`UP`，Flyway JAR/数据库均为V49且失败迁移0，部署启动后的warning/error/exception为0。
- 生产数据验证：绑定巡检已将多岗位账号`xiajun`和`sfglzy777`恢复为`ACTIVE`，清除`MULTIPLE_ACTIVE_ASSIGNMENTS`原因与岗位选择标记，并保留各自有效默认任职；永久删除账号仍维持REVOKED，不受本次恢复逻辑影响。
- 公网与Browser验证：无参数OAuth回调返回302企业微信授权跳转，使用no-store策略、响应体为空且无`Content-Disposition`；`/wecom-auth`显示“无法安全打开中台”和明确凭证错误，页面无框架错误层，控制台错误/警告为0；“返回中台登录”可正常进入`/#/`登录页。真实企业微信授权码交换需由员工在企业微信客户端重新打开工作台完成最终复验。
- 后端专项43项、全量256项（0失败、0错误、3跳过）及Flyway V1→V49通过。本次仍为内部Pilot增量发布，不改变TECH-V0.2正式版本的`Unreleased / NO-GO`状态。

## 11. 2026-09-15 工作台任务下达与完成率分层看板

- 功能提交为`226c084339bbc889a0c7147079e865cc7b3eb839`，已快进合并并推送至GitHub`lzy27272/AIzhongtai:main`。工作台新增直接打开正式任务创建流程的“一键下达任务”；完成率汇总增加门店、部门和员工层级的当日/月度完成率、待提交与逾期数据。
- Flyway V53为集团副总经理角色及现有集团岗位功能方案补齐`task.create`和`task.dispatch`，实际任务目标继续由既有服务端租户、组织树及门店范围策略裁剪。生产只读核验显示1个租户角色和2个已发布/草稿岗位方案版本同时具备两项权限。
- 云端不可变发布版本为`20260915-pilot8-226c084`。后端JAR SHA-256为`9f18b2eede9faa6706e8eb864425eea674f53ada4cbb69350940be3b31aec684`；Web ZIP SHA-256为`46ae6d24888b6c18bca6cc88d5005d8aee771a67e9866984fcc7bfb94d7598a0`；Web `index.html` SHA-256为`d536e400417ee5fb70b19e95d61eae096264d9b34045d15bc29954583f2ce772`，服务器与公网回读一致。
- 部署前生成加密PostgreSQL备份`hotel_ai_os-auto-20260915T092035+0800.dump.enc`，备份任务返回成功，密文及校验文件均为`root:root:0600`。Flyway JAR/数据库均为V53，失败迁移0。
- Core API与Caddy均为`active`，健康状态为`UP`；公网首页返回200，未授权`/api/v1/iam/me`返回401，部署后10分钟Core API warning为0。发布脚本保留旧Core/Web软链接并启用失败自动回滚，本次未触发回滚。
- 验证：Web 102项测试、TypeScript及Pilot生产构建通过；后端集团副总权限迁移与店长分层汇总专项4项通过，完整Flyway V1→V53迁移和生产JAR构建通过。Codex内置浏览器访问线上页面连续超时，因此本轮未完成登录后真实业务账号交互验收，也未改用未经授权的浏览器替代；真实集团副总账号的按钮与下钻数据仍需业务侧复验。
- 本次仍为内部Pilot增量发布，不改变TECH-V0.2正式版本的`Unreleased / NO-GO`状态。
