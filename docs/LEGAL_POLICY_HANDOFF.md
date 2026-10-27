# Papi 协议交付

2026-10-27 后续调整：按用户要求，应用只展示下列公开 H5 协议，已移除随包协议正文和离线正文入口。网络不可用时提供重试。原公开页目前仍描述本地版；云端功能启用前必须更新两份公开页并让已有用户确认新版内容。

更新：2026-10-27。按最新 JPG 技能流程完成两份英文完整正文；应用主语言为英语。联系邮箱按用户要求留空，未生成空 mailto 链接。

## 云端原件与公开页

原生 Google 文档位于已核实账号的 My Drive 根目录下 Papi 文件夹，文件夹 ID `1KhZz1o_OQjM2KGYDc1Cu3MnPtSDge9-D`。仅将两份协议通过 Google Docs Publish to web 发布，未公开文件夹或授予公众编辑权限。

- `Papi_用户协议`，原件 ID `1qnO9dc_sGFgMwUB7Oo74bfkmoU9gz5q2Ruh-Mg7f7Lw`：[公开阅读](https://docs.google.com/document/d/e/2PACX-1vQoWJi7C-CO9-OWqtetngX3xDZerh2viDCfC82GdLjbdsmmRO1XIx59c51M5FGf-rJ7YONmJ7Ph1mG7/pub)。
- `Papi_隐私政策`，原件 ID `19LzlIeEZRwrJZSbOee7VDtO_LKBzyuFyEaE9sllClSQ`：[公开阅读](https://docs.google.com/document/d/e/2PACX-1vTE64ZsiJbXRE47OlspklgrzvUkIqo0CuswoHkkzsm4pe3nbcOFPmrQszIk0Z2-rbNYDVR-LU5tJJ3f/pub)。

正文可选中、复制及编辑；采用原生标题、章节和段落样式、深咖色标题、12 pt 正文及舒适行距。已检查桌面与 390 px 窄屏公开页，修正文档默认宽边距和不换行的长域名造成的溢出。Google 自身的发布横幅保留。

## 应用入口

登录和设置均使用 LegalView，经 CoffeePolicyLibrary 读取 `Papi/Resources/Localization/PapiPolicies.json` 中同一对应公开 URL。WKWebView 使用非持久网站存储，不注入账号、购买或日记数据；外部 HTTPS 链接由用户点击后打开浏览器。保留项目返回按钮和背景，处理加载、失败重试、离线全文和内外屏容器避让。协议正文为英语，离线入口明确标记 English。

随包版本号为 `2026-10-27`。更新下次登录记录的协议版本，不修改历史金币、欢迎奖励、聊天或其他持久化数据。后续手工修改 Google 文档时，需同步随包全文并核对公开页自动重新发布结果。

2026-10-27 原位更新两份文档与随包副本，补充语音房示例人物、留言、礼物及系统合成语音的实际状态；原件全文与公开页面段落已核对一致，邮箱保持空白。

## 文案依据与待补

协议按当前源码说明：本地访客及存储；互关和好友同意；本地发件箱、相机预览、私有投稿、报告隐藏的实际边界；真实 Apple 内购及消耗型金币；退出与删除；权限与外部服务。同步补充 Cloudflare R2 内容请求、IP/技术连接信息及设备缓存，不再将应用描述为完全不联网。

待补事项仅在此说明中记录，不写入正式正文作为开发占位：

- 两份协议的 Contact email 字段仍为空；用户后续提供真实公开邮箱后，同步修改原生文档、公开页和随包全文。
- 运营主体名称、实际运营地区、依法适用的信息及外部服务日志保留设置尚未确认；未编造姓名、地址、法律管辖或固定删除期限。
- 公开运营前核对支持联系方式、实际数据处理与 App Store 隐私标签；有公开 UGC 时仍需真正的审核和举报处理服务。

核对参考：[Apple 审核指南](https://developer.apple.com/app-store/review/guidelines/)、[Apple 隐私信息](https://developer.apple.com/app-store/app-privacy-details/)、[Google 发布说明](https://support.google.com/docs/answer/183965?hl=en)、[Google 隐私政策](https://policies.google.com/privacy)、[Cloudflare 隐私政策](https://www.cloudflare.com/privacypolicy/)。公开链接可用不等于已满足送审条件。

仅完成源码、资源、文档读回与公开页访问/排版核对。未编译、测试或运行 App，未验证 App 内真实 WKWebView 渲染、相机、支付、聊天或远端服务。
