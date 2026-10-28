# 金币与 Apple 内购

更新：2026-10-28。客户端正在迁移到 StoreKit 1 和云端钱包。支付入口仍关闭；商品后台配置或修改客户端开关不代表可以安全收款。

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

- StoreKit 1 客户端包含商品查询、支付队列观察和订单 UUID 关联。新交易须由服务端向 Apple 查询并验签、确认订单归属，再由云端钱包入账；未确认的成功交易不结束。购买开关目前为关闭状态。
- `verify-apple-receipt` 是不使用密钥的服务端验证草稿，尚未部署；客户端传送未完成交易的收据，服务端验证交易、商品、环境和订单关联。Apple 的 `verifyReceipt` 接口已弃用，消耗型收据是否可靠提供订单关联字段尚未实测，缺字段时拒绝入账并保留交易。正式环境已有服务角色限定的幂等入账接口，这不代表端到端充值已经可用。
- 交易失败后客户端保留订单身份及失败记录，防止丢失恢复线索。云端订单取消、中断对账、账户注销竞争处理尚未完成；未完成订单目前会阻止注销。
- Apple 退款通知的接收草稿还没有可靠的后台处理和账务逻辑。钱包不允许负余额，已消费金币的退款、退款撤销及跨设备恢复须先设计并核验，不能假定退款已被处理。
- 审核和 TestFlight 使用 Apple 沙盒交易。正式钱包不得直接接受任意沙盒交易；需要单独隔离审核环境或设计经授权的测试账务，不能只配置 Production 验签后声称审核可用。
- 保留旧的设备快照、交易和余额记录；不得按当前账户或商品 ID 猜测历史交易归属。

## 后续 Apple 配置和验收

商品由用户在 App Store Connect 配置，商品 ID 和对应金币数量需与上表及服务端映射一致。不使用密钥的草稿需要配置正确 Bundle ID 和独立的验证环境。付费协议、银行和税务信息也需符合 Apple 后台要求。

完成订单取消与安全对账、退款及退款撤销处理、通知接收与告警、验签服务部署和密钥配置后，使用 Apple 沙盒验证成功付款、取消、待批准、重复回调、弱网、重启恢复、退款、退款撤销和注销竞争。真实商品可售状态与设备行为另行确认。上述事项完成并确认结果后，才能开启充值；单独修改 `checkoutAvailable` 不能证明支付安全。

参考：[Apple StoreKit 1 订单关联](https://developer.apple.com/documentation/storekit/skmutablepayment/applicationusername)、[完成交易](https://developer.apple.com/documentation/storekit/finishing-a-transaction)、[App Store Server API 密钥](https://developer.apple.com/documentation/appstoreserverapi/creating-api-keys-to-authorize-api-requests)。
