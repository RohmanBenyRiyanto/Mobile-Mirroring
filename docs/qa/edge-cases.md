# Edge cases: what happens to the phone when things go wrong

The app changes some things on the phone (Quick Toggles, mock location, Wi-Fi/mobile data, the API log's proxy, a virtual display). Every change is written to a ledger (`PhoneChangeLedger`, in UserDefaults) *before* it is made and erased when it is undone.

| Scenario | What happens |
|---|---|
| Normal quit, Disconnect, Reset All | Everything is put back at once; the ledger is cleared. |
| `kill` / log-out / Ctrl-C (SIGTERM, SIGHUP, SIGINT) | Handled as a normal quit, so the same restore runs. |
| Crash, `kill -9`, power loss, Mac asleep and lost | The ledger still holds the owed changes. The next session on that phone undoes them and says so. Tested live. |
| Cable pulled while a change is active | Cannot be undone at that moment. Fixed on the next connection (ledger). |
| Phone rebooted | Properties reset by themselves; the restore commands are computed from what the phone shows now, so nothing is applied twice. |
| API log proxy left set (the loopback proxy dies with the app) | A new session removes any `127.0.0.1:` proxy at start. Other proxies (corporate, hotspot) are never touched. |
| Mock location left on | The ledger flag makes the next session remove the test providers and reset the app-op. |
| Wi-Fi / mobile data left off | Restored from the ledger. The switches are not offered over a wireless connection, which they would cut. |
| Two phones | Ledger, proxy port and adb reverse are per serial. |
| Display power, stay awake, show touches | Restored by scrcpy's own cleanup process on the phone even if the app is killed. |
| Virtual display and the app on it | `vd_destroy_content=false`: the app goes back to the phone when the display goes away. |
| Another session wrote new changes while the old ones were being undone | The ledger entry is cleared only if it is still the one that was read. |
