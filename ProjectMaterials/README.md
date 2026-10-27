# Papi 项目素材

Papi 使用 SwiftUI 原生工程，礼物与背包保留，登录为持久化本地访客。

- `DesignReferences/`：蓝湖原稿及 Brew bench 设计参考，继续保留。
- `UIAssets/`：原有项目图标、背景、横幅、插画及礼物，继续本地加载。
- `Typefaces/`：原始字体资料，运行时字体位于 App 的 Fonts 资源目录。
- `Inventory/`：历史审阅联系表及素材元数据，未加入 App target。

2026-10-26 按用户要求将 ContentImages 的 60 张图片及 ContentVideos 的 21 个视频全部改为用户指定的 Cloudflare R2 链接，并删除这两个原件目录及对应的 App 内容副本。完整文件名、哈希、来源和页面归属保存在 `Papi/Resources/Media/CoffeeCollection.json`，不需要重新放回原件。

运行时保留的 UI 资源和字体不受此次迁移影响。远程素材清单、覆盖和网络元数据证据见 `docs/REMOTE_MEDIA.md`。
