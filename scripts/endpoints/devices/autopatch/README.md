# Autopatch Remediation Scripts (V1–V5)

Detect/remediate pairs that keep Windows Update behavior aligned with Autopatch
expectations on Windows 10 and later / Windows Server 2016 and later.

## Policy change (2026-08)

The `DisableWindowsUpdateAccess` value ("Remove access to use all Windows Update
features", managed at `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate`)
is **not supported on Windows 10 and later versions and Windows Server 2016 and
later versions** (see the WSUS Group Policy reference).

All pairs that previously detected/removed that value now manage the supported
WUaaS policy instead:

- `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU\NoAutoUpdate`

(per [waas-wu-settings](https://learn.microsoft.com/en-us/windows/deployment/update/waas-wu-settings)).
`NoAutoUpdate = 1` disables Automatic Updates; detect exits 1 when the value is
present and remediate removes it, exactly as the old pair did for
`DisableWindowsUpdateAccess`.

- `V1/DisableWindowsUpdateAccess/` — the dedicated pair now detects/removes `NoAutoUpdate`.
- `V2`–`V5` — the `DisableWindowsUpdateAccess` array entry was dropped; the
  supported `NoAutoUpdate` entry at the `AU` path was already present in each pair.

Other policies managed by these pairs (`DoNotConnectToWindowsUpdateInternetLocations`,
`WUServer`, `UseWUServer`) are unchanged.
