# Papi

按蓝湖「咖啡社区（34）」39 张设计原稿实现的 SwiftUI 原生 iOS 首版。用户已确认应用名称为 Papi、**保留礼物与背包**、采用**本地访客一键登录**。

打开 `Papi.xcodeproj`，选择共享 scheme `Papi`。工程部署目标为 iOS 17，当前配置使用 Xcode 27.1 / iOS 27.1 SDK 的 Duo API；旧 SDK 必须移除 `PAPI_DUO_SDK` 编译条件，保留普通容器布局回退。Bundle ID 为 `com.papicoffee.collectiveritual`，签名团队尚未配置；商店注册与服务端验单配置需同步，商品清单与商店配置缺项见 [金币与内购](docs/WALLET_AND_IAP.md)。协议已发布公开阅读页。

## 当前能力

- 三页引导、一键登录、协议入口、持久化本地访客、退出与删除本地数据。
- 首页图片/视频瀑布流、动态详情、点赞收藏、本地笔记、照片浏览、咖啡探索。
- 相册导入、相机拍摄、视频播放、本地发布草稿、待审队列及投稿扣币。
- 语音房列表与详情、成员资料、关注/拉黑、消息与图片/语音草稿。
- 钱包、每日签到、等级、完整礼物选择、背包收藏、礼物展示与送礼预览。
- 个人资料、背景、头像、相册、关系、黑名单、六语言界面及设置。
- 固定人物资料映射、统一头像/名字跳转、视频封面和音频切换保护。
- 共用举报/隐藏/拉黑、双向同意守卫、本地消息模型、私有相机预览及加载后退出/删除。

本地数据统一由 `CoffeeHouse` 管理，经 Keychain 保存并读回核验。远程聊天、语音房、送礼及举报服务未连接，界面准确显示预览/草稿状态，不产生虚假送达。真实 Apple 购买入口已开放，仍需在 App Store Connect 核对商品和签名；未进行实际购买验证。

## 交付与验证

最新社区交互见 [社区流程](docs/COMMUNITY_FLOW.md)。详细范围、待补信息和限制见 [交付说明](docs/HANDOFF.md)，设计覆盖见 [设计对应表](docs/DESIGN_COVERAGE.md)，资源来源见 [素材映射](docs/ASSET_MANIFEST.json)。设计、UI 素材和字体资料保留在 `ProjectMaterials/`；内容图片/视频已改为远程加载并删除本地副本，见 [远程素材](docs/REMOTE_MEDIA.md)。

已执行源码人工审阅、工程生成、plist/JSON/资源归属静态检查；**未编译、未运行测试、未启动 App 或模拟器、未做真机或沙盒支付验证**。静态检查结果在 `docs/STATIC_INSPECTION.json`，不能代表编译或运行通过。

工程配置源为 `project.yml`。修改 target 后可使用 `xcodegen generate` 重新生成工程。`Scripts/inspect_project.py` 只检查文件和配置；`Scripts/prepare_assets.py` 仅恢复仍需打包的 UI 素材，跳过远程内容；不重新下载或恢复已迁移的内容图片/视频。

当前咖啡工作流、离线字体和资源处理说明见 [Brew book](docs/BREW_BOOK.md)，全局审核风险与未完成运营配置见 [Review readiness](docs/REVIEW_READINESS.md)。保留旧存储键、媒体别名及交易归属；代码改名本身不构成审核保证。

用户协议与隐私政策、公开链接和邮箱待补位置见 [协议交付](docs/LEGAL_POLICY_HANDOFF.md)。登录与设置共用对应公开 URL，离线副本与初始发布正文一致。
