# Papi 审核工作台（Supabase SQL Editor）

仅限已获项目管理权限的实际审核人员使用。当前没有面向审核员的独立应用，也没有自动审核；未完成审核的内容保持 `pending`，不会因为提交而自动公开。用户已提供联系邮箱 `Papi_service2026@outlook.com` 并确认能收信，实际审核响应流程尚未落实。上线前仍需落实审核人员、处理时效、权限复核和举报处置流程。

在 Papi 项目的 Supabase SQL Editor 中，分别查看待审核投稿、评论和举报；内容与理由属于用户数据，不要导出到公共位置。

```sql
select id, author_id, caption, media_path, media_kind, created_at
from public.coffee_posts where moderation_status = 'pending' order by created_at;

select id, post_id, author_id, body, created_at
from public.coffee_comments where moderation_status = 'pending' order by created_at;

select id, owner_id, kind, media_path, created_at
from public.coffee_profile_images where moderation_status = 'pending' order by created_at;

select id, reporter_id, subject_kind, subject_id, reason, created_at
from public.coffee_reports where review_status = 'pending' order by created_at;
```

图片和视频存放在私有 `coffee-media` bucket。应通过项目管理员的 Storage 界面检查实际文件；不要把 bucket 设为公开，也不要在公开记录中粘贴临时访问链接。

对每一次决定生成并保存一个事件 UUID。复查同一决定或处理网络中断时重用同一个 UUID；不要将 UUID 复用于不同对象或不同决定。以下模板中的值必须由实际审核人员填写；此示例不会自动执行，也不代表任何内容已经获批。

```sql
select gen_random_uuid() as review_event_id;

begin;
-- SQL Editor 的项目管理员已有数据库权限；此声明仅在本事务内启用。
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select public.review_coffee_content(
  'EVENT_UUID'::uuid, 'post', 'SUBJECT_UUID'::uuid,
  'approved', 'REVIEWER_IDENTIFIER', 'REVIEW_REASON'
);
commit;
```

`kind` 为 `post` 或 `comment` 时，决定只能是 `approved` 或 `rejected`。对于举报，`kind` 为 `report`、决定为 `resolved`；只有在完成实际调查和相应处置后才标记处理完毕。审核记录位于 `papi_private.moderation_events`，不向普通 App 账号开放。审核人员应回读对象状态和事件记录；如果执行结果不明确，先确认原事件 UUID 的记录，不要改用新 UUID 重复执行。

头像、背景和相册图片使用单独的审核入口。审核人员在私有 Storage 中检查图片后，在事务内以同样的审核身份声明调用：

```sql
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select public.review_coffee_profile_image(
  'EVENT_UUID'::uuid, 'IMAGE_UUID'::uuid, 'approved',
  'REVIEWER_IDENTIFIER', 'REVIEW_REASON'
);
commit;
```

决定可以是 `approved` 或 `rejected`。每次决定必须使用独立事件 UUID，重试同一决定则沿用原 UUID；同一用户可能多次提交头像或背景，应用显示最新提交且已通过审核的图片。已拒绝和待审核的图片只对所有者可见。

2026-10-28 已在独立 Supabase 测试项目中，以可回滚的合成数据验证待审默认状态、其他用户对待审与已审核帖子的可见性、帖子/评论/头像/举报的审核结果、同一事件重试、冲突事件拒绝和普通账号无审核权限；测试事务已回滚。脚本见 `backend/tests/moderation_hosted_rollback.sql`，其中测试账号限定为该测试项目的合成账号。测试没有验证真实审核人员、SQL Editor 实际操作、审核时效、举报通知或正式运营，不代表已经建立审核团队。

## Collection comments and reports

Collection interactions use separate private tables because collection media is not a cloud user post. In the Supabase SQL editor, a trusted operator can inspect pending items:

```sql
select id, content_id, author_id, body, created_at
from papi_private.editorial_comments where moderation_status='pending' order by created_at;
select id, content_id, comment_id, comment_excerpt, reason, created_at
from papi_private.editorial_reports where review_status='pending' order by created_at;
```

Use the authenticated service-role moderation integration to call `public.review_coffee_editorial_comment(p_id, p_outcome)` with `approved` or `rejected`, and `public.review_coffee_editorial_report(p_id)` after handling a report. These functions record a moderation event. Comments stay private to their author until approved; a report is not a substitute for timely human review. Report snapshots retain the relevant comment text if its author deletes it. Do not put the service key in the iOS app.
