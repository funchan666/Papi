# 金币与 Apple 内购

更新：2026-10-22。按本次新要求启用真实 StoreKit 2 购买代码，覆盖之前“暂不配置充值”的代码开关决定。社区仍为本地版，未接社区后台或 RTC。

## 商品清单

以下金额按 USD 配置参考记录。用户原有 7 个金额和 ID 完全保留，全部调整金币数，新增 2 档。真实本地价格只能由 Apple 返回和确认，客户端不能替代 App Store Connect 定价。商品类型全部为 Consumable（消耗型）。

| 参考金额 USD | 到账金币 | 商品 ID | 本轮 |
| --- | ---: | --- | --- |
| 0.99 | 480 | `rkbybzkkqpeaxovi` | 原 ID、原金额保留 |
| 1.99 | 1,000 | `yiyfivvjmkdiuqus` | 原 ID、原金额保留 |
| 2.99 | 1,600 | `mqtzlpvknayrxwce` | 新增 |
| 4.99 | 2,800 | `vguhlyrrsyfaswwv` | 原 ID、原金额保留 |
| 9.99 | 6,000 | `qqopbybcdridrsjl` | 原 ID、原金额保留 |
| 14.99 | 9,600 | `wspjnqfkxvmdlrya` | 新增 |
| 19.99 | 13,200 | `kokiljjwycwbpasa` | 原 ID、原金额保留 |
| 49.99 | 36,000 | `nylrtdzhiqgywsrh` | 原 ID、原金额保留 |
| 99.99 | 78,000 | `lkcdocdwdjjjmdfr` | 原 ID、原金额保留 |

可复制商品名称和英文说明见 [COIN_PRODUCTS.json](COIN_PRODUCTS.json)，名称控制在 30 字符以内、说明 45 字符以内，按 [Apple 商品信息限制](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information) 静态核对。该文件是配置清单，不冒充官方导入格式。

## 金币闭环

- 新本地账号第一次一键登录赠送 800 金币；余额、welcomeGrant 与唯一流水在同一 Keychain 快照写入并读回后才显示“首杯咖啡礼券”。再次登录不重复赠送，关闭礼券会保存已读；中断重启可继续展示尚未关闭的礼券，不重复加币。旧账号不补发首次奖励。删除后创建的新本地身份按新账号规则处理；无后台无法限制跨设备或重复建号奖励。
- 图片投稿 40、视频投稿 80 金币。确认框明确消费后才原子扣币并保存到本人私有审核队列，不购买审核通过或公共曝光；当前没有审核服务，投稿仍不会公开。删除投稿不退回已确认使用的保存费用。
- 背包收藏：Sending love 80、Peach 120、Sweet brew 180、Three wishes 260、Little bird 360、Coffee beats 520、Dream ride 900、Café royalty 1,400。数量和总价先确认，扣币与库存同一快照落盘。已拥有礼物的展示/取消展示免费，礼物预览免费，不包装为远端赠送。
- 文字聊天、聊天图片、语音消息、视频通话、关注、好友申请、举报与拉黑均无扣币路径。互关/好友同意规则继续有效。
- 每日签到继续提供 10–70 金币，七次一个循环、UTC 日界线。
- 首页、个人中心、礼物页、钱包均读取同一 Published 状态；充值页顶部余额常驻，Apple 到账、签到、消费、退款调整写入成功就刷新。退款按原始入账流水回收，若余额为负，禁止进一步付费操作，后续奖励/充值先填补差额。
- 不足时显示消费额与当前余额，点 Recharge 进入充值页；动态草稿留在持久层，礼物选择留在原页面。取消不扣币，不自动重新消费。

## 新增配方用途

Four pours, brighter finish 120、A rounder cup 180、The iced window pour 240 金币，账户内各解锁一次。已解锁配方复用、记录冲煮、再冲基准杯和双杯品鉴均免费；免费基础配方两份。充值页、详情确认与流水使用同一配方数据。详情见 [BREW_BOOK.md](BREW_BOOK.md)。

## Apple 购买与恢复

进入钱包、选择档位、首次登录均不请求商品。只有点击 Buy，才调用 `Product.products(for:[selectedID])` 查询当前商品；查不到、网络失败或类型不是消耗型则停止，无假到账。初始档位明确标 USD reference；查询后展示 Apple 的 displayPrice，系统购买页确认最终价格。若 Apple 返回的 USD 售价与固定参考金额不一致，会阻止购买并提示检查商店配置；其他地区采用 Apple 本地化价格。

SwiftUI 环境的 PurchaseAction 提供真实系统支付 UI 与所属 scene 上下文。每次购买先保存独立 appAccountToken、原始访客、商品和当次金币数量。后续只凭已验证交易中的 token 查原始订单，不能按当前账号、当前页面或 SKU 推定归属。旧六档不再售卖，仅保留冻结的旧数量用于旧 token 订单恢复。取消与明确的商品购买错误移除当前意图，原始订单条款保留以供可能的后续交易核对；待批准/结果不明确时保留意图并阻止再发起扣款，可通过 Recover purchases 同步 Apple。未知或缺失归属、未验证、数量异常的交易不入账、不 finish。

Transaction.updates 常驻监听，启动/回前台扫描 unfinished。已验证交易按 ID 幂等，余额、原始金币数和流水经 Keychain 写入并读回后才 finish。退款从当笔真实入账数回收，后续调整档位不会改写历史交付量。退出/删除与支付发起互斥；删号保留旧访客和交易归属记录，新访客不能继承旧购买。Recover purchases 不会恢复已经 finish 的消耗型余额到新访客，也不承诺跨设备同步。

## 仍需 App Store Connect / 签名配置

源码已能发起真实购买，但未登录或修改 App Store Connect，也未创建/验证任何商品。当前 Bundle ID 仍为暂定 `com.papi.coffee`，开发者 Team 为空。需确认该 App 的真实 Bundle ID/签名团队，在同一 App 下核对原 7 款、创建新增 2 款消耗型商品，并按表设置参考定价、显示名称、说明、审核截图和销售地区；完成协议、税务及银行相关要求。若参考币种并非 USD，需要在商店侧按实际参考币种确认定价，原给定数值和 ID 不擅自改变。

不配置可售商品时 Apple 将返回不可用，代码不会模拟支付。真实设备/沙盒购买、取消、Ask to Buy、重复通知、退款、杀进程恢复、Keychain 重启读回及不同地区价格均未运行验证。遵循默认不编译、不测试、不启动要求。

依据：[Apple 商品查询](https://developer.apple.com/documentation/storekit/product/products(for:))、[SwiftUI PurchaseAction](https://developer.apple.com/documentation/storekit/purchaseaction)、[交易更新](https://developer.apple.com/documentation/storekit/transaction/updates)。本轮读取官方 Markdown 与本机 iPhoneOS SDK StoreKit / SwiftUI 声明，只用于 API 静态核对。
