# Android device acceptance tests (not yet executed)

Use two test phones and synthetic messages; do not send to real contacts without consent.

1. Reject default-role and permission dialogs: no crash, no provider mutation, no demo messages presented as real on Android.
2. Grant role then SMS/notification permissions. Receive one Persian multipart SMS while foreground, background and process removed from recents. Verify one complete inbox row and private notification.
3. Send single and multipart messages on each SIM; compare provider outbox/sent/failed states with recipient phone. Confirm delivery indicator only changes after carrier report.
4. Tap send twice rapidly; verify one queued message. Cancel before five seconds; verify no SMS is transmitted. Attempt cancellation after deadline; cancellation must report failure.
5. Kill process during grace period; check alarm dispatch, no duplicate send after reopening. Reboot during grace period; queue must be cancelled. Force-stop restrictions must be explained.
6. Airplane mode/no service/invalid default SIM: preserve draft, mark failures, never claim delivered. No automatic retry of an ambiguous radio request.
7. Delete confirmation: Cancel leaves the provider unchanged; Confirm removes only the chosen message. Revoke default role then retry: reject mutation.
8. Read older pages containing identical timestamps; no duplicates or skipped IDs. New-message refresh preserves the number of loaded pages.
9. Archive conversation, restart, unarchive. Unread filter reflects incoming provider read flag. Check text scaling and RTL with Latin phone numbers.
10. Open sms/smsto links in cold and warm activity; prefill only, never send automatically.
11. Verify MMS warning before default role. This build does not retrieve MMS; do not use it as default on an MMS-dependent device.
12. Verify APK signature and application ID before upgrading an existing install; never uninstall a user's copy without exporting needed local drafts/settings.
