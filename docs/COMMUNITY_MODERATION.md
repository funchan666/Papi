# Papi moderation operations

The Papi Supabase project is `cquoffowtjnxmgaxavym`. This is an operator workflow for the deployed schema; the app has not been switched to it yet.

In the Supabase dashboard, restrict project access to authorized moderators. Use the Table Editor to review `coffee_posts` and `coffee_comments` with `moderation_status = pending`. A post's `media_path` is an object in the private `coffee-media` bucket. Review the image or video and caption together before changing its status to `approved` or `rejected`. Never approve content solely because it was submitted or paid for. An approved post can be read by users allowed by its row policies; pending and rejected content stays private to its author.

Review new `coffee_reports` rows and the referenced profile, post, comment or message. Reporting immediately hides the reported item from the reporter through row policies. Escalate confirmed abuse and remove or reject violating material using the dashboard; record internal handling separately until a dedicated moderation workflow is implemented. For messages, restrict staff access and inspect only what is needed to assess the report. Do not add a service-role key to the app.

The dashboard does not currently provide an assigned-reviewer workflow, review deadlines, notifications, appeal handling or a complete account suspension tool. A real support contact is still required before launch. These manual steps are not evidence that any report has already been reviewed.
