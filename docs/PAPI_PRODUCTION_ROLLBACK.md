# Papi 正式实时功能暂停与恢复

仅供有正式项目管理权限的操作人员在真机测试遇到问题时使用。执行前确认项目为 `cquoffowtjnxmgaxavym`。不要清除已有账户、本地档案、媒体、队列或购买记录。

## 停止新语音和通话

在 Supabase SQL Editor 的一个事务中执行：

```sql
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select public.set_voice_runtime(false);
select public.set_call_runtime(false);
commit;
```

这会拒绝新的语音/通话授权，并将活动会话排队清理。保持 `papi-livekit-cleanup` 任务运行，直至待处理撤销任务归零；如果清理失败，先查 Edge Function 日志和 LiveKit 状态，不要直接删除队列。已经发出的短期访问令牌和实际断线仍需观察，开关变化本身不证明所有设备已断开。

```sql
select count(*) as pending_voice from papi_private.voice_revocations where completed_at is null;
select count(*) as pending_calls from papi_private.call_revocations where completed_at is null;
select jobname,active from cron.job where jobname='papi-livekit-cleanup';
```

如果必须暂停注销，先检查是否有 `state='requested'` 的注销；关闭注销开关会阻止这些请求继续完成，因此应先处理完成或明确记录需要恢复的请求。保持收据和私有记录，不要清理。

```sql
select count(*) as pending_deletions from papi_private.account_deletions where state='requested';
-- 仅在没有待完成请求、或已明确接受暂停重试时执行：
update papi_private.account_deletion_runtime set enabled=false where singleton=true;
```

仅当实时功能已停用、撤销队列为空且没有需要该任务清理的会话时，才考虑暂停后台任务：

```sql
select cron.alter_job((select jobid from cron.job where jobname='papi-livekit-cleanup'), active:=false);
```

恢复前检查对应故障、已发布协议、服务密钥和设备测试结果；先启动清理任务，再按需启用 `public.set_voice_runtime(true)`、`public.set_call_runtime(true)` 和注销数据库开关，并逐项读回验证。不要为了让功能显示正常而跳过清理任务或检查。
