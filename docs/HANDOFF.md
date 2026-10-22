# Papi 原生首版交付

更新：2026-10-21。用户确认优先于 JPG 的默认礼物移除规则：**礼物不移除**，登录采用本地访客。

## 已实现范围

以 `DESIGN_COVERAGE.md` 为页面对照。应用入口为 `Papi/App/PapiApp.swift`，功能源码在 `Papi/Features/`；四个 Tab 保持挂载，导航由同一 router 管理，资料、余额、签到、关系、黑名单、草稿和背包共用 `PapiStore`。

本地访客保存稳定 UUID，一键登录重新打开同一访客。退出保留数据，删除创建新身份并清除旧访客媒体；删除失败记录待清理目录，下一次解锁重开重试。旧购买交易 ID 和身份墓碑保留，不能用于给新访客补发旧订单。

余额初始为 0。每日 UTC 日期可签到一次，第 1–7 次分别奖励 10–70 币，循环累计；保存本地帖子消耗 10 币。礼物收藏按页面价格扣币，同一快照增加库存和记账。个人主页可展示已持有礼物。向成员或房间的礼物入口保留，但在未连接收件方时只预览，不扣币、不减少库存、不声称送达。

图片、视频、语音草稿保存到访客独立目录。选中照片/视频用 Apple PhotosPicker，拍摄用真实相机界面，录音使用真实麦克风权限。播放器使用 AVPlayer，切换媒体和离开页面释放/暂停旧播放。预览房间不会启动麦克风、建立通话或伪造远端成员活动。

## 设计和资源

- 实际采用 JPG、ui-design-reference、ui-taste、Duo，本轮补充 Impeccable 的边界状态参考；缺少语音房纯背景时使用 Garden gpt-image-2 与宿主 imagegen，保留生成提示和原图。
- 39 张设计原稿保存于 `ProjectMaterials/DesignReferences/Lanhu/`，`sources.json` 记录来源。
- 用户原件包括 105 张 UI PNG、60 张内容照片、21 个视频，全部保留；新生成的纯语音房背景另放在 `UIAssets/Generated/`。
- 运行时包含 106 个 imageset、独立 AppIcon 和背景颜色、21 个视频及各自的实际首帧封面。原始设计图、脚本和素材联系表不进入 App target。
- 用户已授权人物照片分别作为独立示例资料。`person00…person07` 固定对应 Mia、Luna、Avery、Sam、Alex、Noah、Quinn、Charlie，头像/主页/房间/聊天共用同一 ID 和原图。名称为示例昵称，不声称是照片中真实人物的姓名；不把不同照片合并为同一人。
- UI 复用用户原始图标、横幅、插画和礼物，未引入 SF Symbols 或系统图标库。AppIcon 仅在运行时副本做 1024px RGB 包装，原始图不变。
- 运行时资源源文件合计约 89.0 MiB，主要是视频。这不是 IPA、商店下载或安装体积，未打包测量。

## Duo 静态适配

当前机器 SDK 为 iOS 27.1。已核对 SDK 声明和 Apple 文档，使用容器尺寸、安全区、container content margins、active division/occlusion reserved regions 和 toolbarVerticalEdge；通过 `PAPI_DUO_SDK` 条件隔离新 API，并保留 iOS 17 普通布局。

导航、访客、草稿与播放对象不以屏幕尺寸重建；四 Tab 的同一布局实例可切换底栏/侧栏。弹窗按可用区域定位，主要图标按钮避让保留区域。未虚构设备尺寸。折叠姿态、内外屏连续性、RTL、键盘、字号及实际遮挡仍需后续真机/模拟器视觉验证。

参考：[Apple Duo 指南](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo)。

## 购买恢复边界

`PapiCommerce.purchasesConfigured` 为 false，六个 `com.papi.coffee.coins…` 标识仅为待配置名称，不能视为已上架商品。商品价格只取 Apple 返回的 displayPrice，未使用原稿示意价格假装真实售价。

已写入 StoreKit 2 商品读取、购买前持久化原始 owner、appAccountToken、Transaction.updates、unfinished 扫描、幂等入账、读回确认后 finish、原订单身份校验与撤销处理。未知/旧身份/未验证交易保留且不 finish；购买结果不明确时保留原始意图，不按当前账号或 SKU 推断归属。没有进行沙盒或真实付款验证。

参考：[Apple Transaction.updates](https://developer.apple.com/documentation/storekit/transaction/updates)。

## 本轮补齐

- 六种界面语言统一走运行时本地化，共 408 条英文基准文案及 5 组翻译，覆盖主流程、表单、动态数量、状态/错误、无障碍标签和本地版协议。首次使用选择受支持的系统语言，否则回退英语；已保存的语言选择保持。日期/余额使用系统格式化，阿拉伯语支持 RTL 与返回箭头方向。
- 六套相机/麦克风用途说明进入 InfoPlist 本地化资源。系统权限界面的语言仍由 iOS 决定，不模拟系统授权。
- 新导入视频使用 AVAssetImageGenerator 异步提取实际封面并保存在视频旁，失败保留原始视频与项目占位图。并发请求共用任务，访客删除后不重建旧目录。
- 消息列表包含纯图片或纯语音草稿，清空入口经确认移除聊天草稿引用；不会清空个人资料或日志。
- 视频/语音/录音统一音频会话所有权，旧播放器的退出回调不能关闭新录音；中断时停止/暂停，视频失败可重试，语音缺失或播放失败有反馈。
- 照片浏览补充放大拖动；切换容器尺寸时限制平移范围。登录按钮按原稿移至插画下方并填满可用宽度，恢复返回引导入口。以上布局改动尚未运行查看。

视频封面 API 依据：[Apple AVAssetImageGenerator.image(at:)](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator/image(at:))，已读取官方 Markdown 与本机 SDK 声明。

## 用户已决定暂缓

用户本轮明确回复：人物独立示例映射允许；签名和真实充值“暂时不配置”；协议“暂用本地”。记录见 `CONFIRMATIONS.md`。

- 暂定 Bundle ID `com.papi.coffee` 和未配置的开发者团队保持；真实购买关闭，不重新请求这些资料。
- 本地版说明继续随 App 提供。将来公开发布时再提供有效支持渠道与正式协议。
- 远端聊天、语音、礼物、举报、内容服务和推送仍不接通，符合当前本地版范围。入口保留并准确说明能力，不显示假成功。

## 剩余验证边界

所有上述改动目前只有源码与资源证据。编译、模拟器、真机、Duo 姿态、音视频与权限实机行为、屏幕截图还原、语种换行仍待明确授权后验证。原始图片里的英文、品牌/咖啡品种名、示例内容原文及用户输入不做替换；译文尚未由各语种母语者审校。

## 已执行与未执行

已执行：源文件与资源引用人工审阅、XcodeGen 工程生成、plist/JSON 解析、PBX 源码和资源构建阶段归属检查、图片文件存在性、21 组视频与封面匹配、AppIcon 格式、原始材料排除、翻译语言/占位符完整性、六组 InfoPlist 本地化文件及空白检查。检查脚本仅读取源码/配置/文件，结果见 `STATIC_INSPECTION.json`。

未执行：Swift/Xcode 编译、静态分析器、单元或 UI 测试、App/模拟器/真机运行、截图对比、Duo 姿态验证、远端服务、沙盒支付与 App Store 验证。因此当前交付是原生首版源码与资源，不能声称运行通过或已达到逐像素视觉验收。
