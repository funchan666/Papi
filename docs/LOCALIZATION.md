# 本地化维护

资源入口：Papi/Resources/Localization/PapiTranslations.json。

每个英文基准文案对应 es、th、ar、vi、ko 五组译文；英语直接使用原文。PapiText、PapiTextButton、PapiInput 与 papiAccessibilityLabel 依据当前 locale 统一查找。动态文案使用 {0}、{1}，允许翻译调整位置；静态检查核对占位符集合。

用户自己的姓名、简介、帖子、笔记和聊天文本使用 verbatim，不随语言切换被改写。示例帖子的原文、品牌及咖啡品种名称、图片内嵌文字保持原样。日期和余额继续由 SwiftUI 的原生格式化显示。

相机和麦克风权限说明另在 InfoPlistLocalizations 下的六个 lproj 中管理。应用内选择语言不会假装改变 iOS 系统授权界面的语言。

新增操作或错误文案时补齐五组翻译；新增需要翻译的动态句子时添加完整模板，不能只翻译前后片段。新资源目录已加入 PBXResourcesBuildPhase。当前译文为开发实现，尚未经过母语审校或设备上的长文本视觉验证。

2026-10-22：新增冲煮、重冲、品鉴比较与配方收费说明均补入既有六语言流程；当前键数量见 STATIC_INSPECTION.json。新字体为两组离线 OFL 字族，缺字采用系统已安装字形回退。编辑图集的人物简介与所提供咖啡内容保留其英文原文，不虚构不同语言的用户输入；原图文字不通过本地化层重绘。译文仍待母语者和实际布局检查。
