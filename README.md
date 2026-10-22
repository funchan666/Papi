# Papi

按蓝湖「咖啡社区（34）」39 张设计原稿实现的 SwiftUI 原生 iOS 首版。用户已确认应用名称为 Papi、**保留礼物与背包**、采用**本地访客一键登录**。

打开 `Papi.xcodeproj`，选择共享 scheme `Papi`。工程部署目标为 iOS 17，当前配置使用 Xcode 27.1 / iOS 27.1 SDK 的 Duo API；旧 SDK 必须移除 `PAPI_DUO_SDK` 编译条件，保留普通容器布局回退。Bundle ID 暂为 `com.papi.coffee`，签名团队尚未配置；用户已决定本轮暂不配置签名和真实充值，继续使用本地版协议。

## 当前能力

- 三页引导、一键登录、协议入口、持久化本地访客、退出与删除本地数据。
- 首页图片/视频瀑布流、动态详情、点赞收藏、本地笔记、照片浏览、咖啡探索。
- 相册导入、相机拍摄、视频播放、本地发布草稿及发帖扣币。
- 语音房列表与详情、成员资料、关注/拉黑、消息与图片/语音草稿。
- 钱包、每日签到、等级、完整礼物选择、背包收藏、礼物展示与送礼预览。
- 个人资料、背景、头像、相册、关系、黑名单、六语言界面及设置。
- 固定人物资料映射、新导入视频封面、图片/语音草稿列表和音频会话切换保护。

本地数据统一由 `PapiStore` 管理，经 Keychain 保存并读回核验。远程聊天、语音房、送礼及举报服务未连接，界面准确显示预览/草稿状态，不产生虚假送达。Apple 购买代码已准备，但真实商品未配置，购买默认关闭。

## 交付与验证

详细范围、待补信息和限制见 [交付说明](docs/HANDOFF.md)，设计覆盖见 [设计对应表](docs/DESIGN_COVERAGE.md)，资源来源见 [素材映射](docs/ASSET_MANIFEST.json)。原始资料保留在 `ProjectMaterials/`，未加入 App target。

已执行源码人工审阅、工程生成、plist/JSON/资源归属静态检查；**未编译、未运行测试、未启动 App 或模拟器、未做真机或沙盒支付验证**。静态检查结果在 `docs/STATIC_INSPECTION.json`，不能代表编译或运行通过。

工程配置源为 `project.yml`。修改 target 后可使用 `xcodegen generate` 重新生成工程。`Scripts/inspect_project.py` 只检查文件和配置；`Scripts/prepare_assets.py` 按现有映射复制素材及提取视频封面，依赖 Pillow、ffmpeg、sips。
