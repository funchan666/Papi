# 金币与 Apple 内购

更新：2026-10-28。客户端使用 StoreKit 1 和云端钱包。正式环境收据验证服务已部署，云端充值开关已开启；客户端更改尚未编译或经过支付验证。

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

## 当前支付状态

- StoreKit 1 客户端包含商品查询、支付队列观察和订单 UUID 关联。新交易由服务端向 Apple 验证收据，核对订单、商品和交易，再由云端钱包入账；未确认的成功交易不结束。客户端读取云端购买开关并在发起前再次核对；正式环境开关已开启。
- `verify-apple-receipt` 已部署正式 Supabase，购买到账不依赖通知地址、数字 App ID 或 Apple API 密钥。Apple 的 `verifyReceipt` 接口已弃用。收据没有账号绑定字段时，服务端通过首次认领和交易号防重处理，不能据此证明 Apple 账号与 Papi 账号的绑定。
- 交易失败后客户端保留订单身份及失败记录，通过云端取消订单并释放购买状态。新订单会记录是否已开始提交 Apple；可确认尚未提交的订单在中断后可重建并取消。已提交或历史订单仍需谨慎对账；未完成订单会阻止注销。
- Apple 退款通知已准备签名校验和记录入口，但还没有后台账务处理；配置完成后，非单次购买通知会返回重试状态，不冒称已处理。钱包不允许负余额，已消费金币的退款、退款撤销及跨设备恢复须先设计并核验，不能假定退款已被处理。
- 审核和 TestFlight 使用 Apple 沙盒交易。正式钱包不得直接接受任意沙盒交易；需要单独隔离审核环境或设计经授权的测试账务，不能只配置 Production 验签后声称审核可用。
- 保留旧的设备快照、交易和余额记录；不得按当前账户或商品 ID 猜测历史交易归属。

## 后续 Apple 配置和验收

商品由用户在 App Store Connect 配置，商品 ID 和对应金币数量需与上表及服务端映射一致。付费协议、银行和税务信息也需符合 Apple 后台要求。

正式环境当前只接受 Production 收据；审核和 TestFlight 使用的 Sandbox 收据不会到账，需另行完成与正式钱包隔离的支持。退款及退款撤销自动账务处理、部分中断订单对账和旧交易恢复仍未完成。用户要求不运行支付检查，因此成功付款、取消、重试及实际到账均未验证。

参考：[Apple StoreKit 1 订单关联](https://developer.apple.com/documentation/storekit/skmutablepayment/applicationusername)、[完成交易](https://developer.apple.com/documentation/storekit/finishing-a-transaction)、[App Store Server API 密钥](https://developer.apple.com/documentation/appstoreserverapi/creating-api-keys-to-authorize-api-requests)。
