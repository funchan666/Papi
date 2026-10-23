# Papi 全屏背景与边缘布局

2026-10-23，源码静态检查与增量修正。保留 SwiftUI、原始咖啡主题素材和已有导航状态。

本次按“去掉安全区域”处理页面背景的空带：背景和栏位底色延伸至屏幕边缘；返回、发送、购买、协议和输入等前景控件仍避开系统遮挡。没有全局忽略键盘区域，也没有隐藏系统状态栏或 Home 指示条。

## 公共修正

- `PapiScreen`：36 处调用共用背景规则；容器边距只作用于前景，背景单独绘制并铺满。
- `PapiDeviceContainer`：在前景几何测量之外提供完整主题底图，覆盖根窗口与 sheet 的边缘底色。
- 主 Tab：移除会截断页面背景的整块内容裁切，保留图片和滚动容器自身的局部裁切。四个页面仍稳定挂载，不因边缘布局调整重建导航或业务状态。
- 底部 Tab / Duo 侧栏：只让咖啡色栏位背景延伸到系统边缘，图标与标签的布局不忽略系统遮挡。
- 聊天输入栏：咖啡色底色延伸至底边；消息滚动支持交互式收起键盘，输入栏保留系统键盘避让。
- 引导页：分页图片容器延伸到屏幕边缘；翻页、跳过操作仍在前景中。原图的适配策略保留，宽容器中不强行裁掉图上的标题。
- 个人资料与咖啡桌的外层标题组合：补齐主题背景，避免外层与内部页面使用不同底色。
- 4 处 sheet 入口：统一主题 presentation background，覆盖发布、举报、礼物、协议、录音等路由；相机预览使用深色房间背景。系统拍摄界面的全屏行为保留。
- 确认、欢迎、举报成功和账号操作弹窗：现有遮罩继续铺满，弹窗正文仍使用可用区域和滚动容器。

## 静态检查证据

- 全局检查 30 个 Swift 文件，36 处 `PapiScreen` 调用、4 处 sheet 入口、1 处系统拍摄 full-screen cover。
- 独立 Swift 语法树解析没有新增未解决异常；语法解析器已有的两段乘法表达式识别限制仍仅在内存中用等价空格处理，原表达式未修改。
- 资源、配置与源码引用检查无新增发现；`git diff --check` 无问题。
- 新增的 presentation background 接口已与本机 SwiftUI SDK 声明核对，最低可用系统 iOS 16.4，项目最低系统 iOS 17。
- 未编译、未测试、未启动 App、模拟器或真机；未产生本次变更的运行截图。

仍需实际视觉验证：窄屏与横屏、较大字体、阿拉伯语 RTL、键盘开合、sheet 展开/收起、Duo 侧栏换边及内外屏连续性。源码检查不构成“所有 UI 无异常”的运行验收。

依据：[Apple — Adding a background to your view](https://developer.apple.com/documentation/swiftui/adding-a-background-to-your-view)、[presentationBackground](https://developer.apple.com/documentation/swiftui/view/presentationbackground(alignment:content:))。背景延伸与前景避让分别处理。
