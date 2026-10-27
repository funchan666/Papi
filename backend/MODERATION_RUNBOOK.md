# Papi 审核工作台（Supabase SQL Editor）

仅限已获项目管理权限的实际审核人员使用。当前没有面向审核员的独立应用，也没有自动审核；未完成审核的内容保持 `pending`，不会因为提交而自动公开。联系邮箱尚待补充。上线前仍需落实审核人员、处理时效、权限复核和举报处置流程。

在 Papi 项目的 Supabase SQL Editor 中，分别查看待审核投稿、评论和举报；内容与理由属于用户数据，不要导出到公共位置。

```sql
select id, author_id, caption, media_path, media_kind, created_at
from public.coffee_posts where moderation_status = 'pending' order by created_at;

select id, post_id, author_id, body, created_at
from public.coffee_comments where moderation_status = 'pending' order by created_at;

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

当前仅准备了数据库工作流，并未验证 SQL Editor 的实际执行、审核时效或举报通知；不能把这份说明当成已经建立运营团队或完成端到端审核验收。
