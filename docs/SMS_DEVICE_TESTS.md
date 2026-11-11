# Android device acceptance tests (not yet executed)

Use two test phones and synthetic messages; do not send to real contacts without consent.

1. Reject default-role and permission dialogs: no crash, no provider mutation, no demo messages presented as real on Android.
2. Grant role then SMS/notification permissions. Receive one Persian multipart SMS while foreground, background and process removed from recents. Verify one complete inbox row and private notification.
3. Send single and multipart messages on each SIM; compare provider outbox/sent/failed states with recipient phone. Confirm delivery indicator only changes after carrier report.
4. Tap send twice rapidly; verify one queued message. Cancel before five seconds; verify no SMS is transmitted. Attempt cancellation after deadline; cancellation must report failure.
5. Kill process during the five-second grace period; check alarm dispatch and no duplicate sends. Reboot during the grace period: only immediate queued sends must be cancelled. Future scheduled SMS should be re-armed after boot; force-stop and Doze may defer sends.
6. Airplane mode/no service/invalid default SIM: preserve draft, mark failures, never claim delivered. No automatic retry of an ambiguous radio request.
7. Delete confirmation: Cancel leaves the provider unchanged; Confirm removes only the chosen message. Revoke default role then retry: reject mutation.
8. Read older pages containing identical timestamps; no duplicates or skipped IDs. New-message refresh preserves the number of loaded pages.
9. Archive conversation, restart, unarchive. Unread filter reflects incoming provider read flag. Check text scaling and RTL with Latin phone numbers.
10. Open sms/smsto links in cold and warm activity; prefill only, never send automatically.
11. Verify MMS warning before default role. This build does not retrieve MMS; do not use it as default on an MMS-dependent device.
12. Verify APK signature and application ID before upgrading an existing install; never uninstall a user's copy without exporting needed local drafts/settings.

13. Device-specific false-failure regression: send a short Persian SMS between two phones. Verify that an Android SENT callback with resultCode=0 is shown as unconfirmed (not failed); a later successful delivery report must update the provider row and dismiss any stale failure notice. Test true radio-off and invalid-SIM errors separately.
14. Hold the right-side send arrow; select a date/time 10+ seconds ahead; confirm, close and reopen the app, confirm queued item is still visible. Cancel before due time. Verify 5-second undo behavior is unchanged.
15. Select 51 and 500 consenting contacts; validate duplicate removal, selection summary, confirmations and message counts. Confirm carrier and OS rate-limit responses are clearly shown without repeated retries or overwhelming UI notifications.
16. Inspect Persian date/time picker, chat bubbles, editor preview, settings version/website links, right-side send button, and notification appearance on at least two Android ROMs. System notification background is controlled by Android; app cannot guarantee a glass effect on every lock screen.
17. Verify GitHub Actions artifact, stable release signing, upgrade over existing install, and GitHub Releases APK asset. The GitHub repository is private; the Releases URL is not a public download without repository access.
