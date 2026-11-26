# Grok Bot Desktop

A local bridge that lets **Grok Bot** see and control the desktop of this Windows PC. Grok Bot reaches it only through a command-line client on the PC: the fast native client `gbd.exe` (or `gbd.cmd`), or the PowerShell CLI `grokbot-desktop.ps1` (`deskctl.ps1` is an alias). Every command runs through Grok Bot's Shell on the PC, which you approve.

Flow: `gbd.exe / grokbot-desktop.ps1 → HTTP + token → Grok Bot Desktop on 127.0.0.1 → your desktop`.

## Safety (not negotiable)

- The server **only listens on 127.0.0.1**, never on `0.0.0.0`. The clients have no address override.
- Every request carries a token (`Authorization: Bearer` or `X-Deskctl-Token`). It is created at install time and stored in `%LOCALAPPDATA%\GrokBotDesktop\token`, readable only by your user. The clients read it themselves and never print it.
- Control **always starts off**. Only the tray icon menu can turn it on or off (**Turn on** / **Turn off**). The CLI `on` / `off` commands are refused.
- While off, there are no screenshots, clicks or keys: actions answer `kill_switch_off`. `status` still works.
- While on, the icon shows a red mark and a notification says "Grok Bot Desktop is on".
- The switch is checked before every batch step, inside every wait, and between typing chunks: choosing **Turn off** stops a running batch, `open`, `type` or `selftest` with `kill_switch_off`.
- No telemetry. It never reads or sends cookies, passwords or other credentials, and never exposes the port to the network.
- Windows does not let a non-elevated process control an elevated (UAC) window; `focus` then fails with `focus_failed`. Nothing here ever asks for elevation.
- Leave it off when you are not using it. Do not share the token.

## Requirements

Windows 10 or 11 with Windows PowerShell 5.1 and .NET Framework 4.x (both ship with Windows). Nothing else to install, no administrator rights needed.

## Install

**WinDesk Bot** installs this program for you. It downloads the official release zip, checks the SHA-256, runs `scripts\install.ps1` and starts the app. You approve the commands on your PC, then choose **Turn on** from the tray icon.

### Manual install

If you are installing by hand, copy this folder to the PC and, from inside it, in PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

This copies the app to `%LOCALAPPDATA%\GrokBotDesktop`, creates the token and builds the fast client `gbd.exe` with the `csc.exe` that ships with .NET Framework (`scripts\build-client.ps1`, current user only). If an older install exists in `%LOCALAPPDATA%\deskctl`, its token is migrated and the old folder removed. Autostart stays **off** unless you pass `-Autostart`.

Start:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\GrokBotDesktop\scripts\start.ps1"
```

A **Grok Bot Desktop (off)** icon appears in the tray. Right-click it, then **Turn on**.

Check it:

```powershell
& "$env:LOCALAPPDATA\GrokBotDesktop\gbd.exe" status
& "$env:LOCALAPPDATA\GrokBotDesktop\gbd.exe" selftest
```

In Task Manager the server shows as `powershell.exe` with `GrokBotDesktop` in its command line. The tray icon is taken from the installed Grok Bot app when it can be found (`%LOCALAPPDATA%\Programs\*grok*\`, `Grok Bot`, Program Files); otherwise a fallback icon is used.

## Fast client: gbd

Each call to `grokbot-desktop.ps1` starts a new PowerShell (about 1–3 s). `gbd.exe` is a tiny native client (C#, built on the PC) that speaks the same protocol with the same token, only to `127.0.0.1`, and answers in about 150 ms. Every command prints one JSON line and exits 0 when `ok` is true. `gbd.cmd` is a wrapper that builds `gbd.exe` if it is missing.

```text
gbd status
gbd open <app|url|uri> [--wait <title>] [--args "<arguments>"] [--timeout ms]
gbd screenshot [--full] [--monitor all|N | --window active | --hwnd <id>] [--max-width N] [--format png|jpg] [--quality 1-100]
gbd type <text> [--gap ms]
gbd key <combo>
gbd click <x> <y> [--button left|right|middle] [--double] [--space screen|image]
gbd move <x> <y> [--space screen|image]
gbd scroll <dy> [--x N] [--y N]
gbd focus <title> | --hwnd <id>
gbd foreground
gbd windows
gbd wait --title <text> [--timeout ms] [--foreground] [--gone]
gbd launch <program> [--args "<arguments>"] [--wait-title <text>] [--timeout ms]
gbd batch <json> | --b64 <base64 json> | --file <steps.json> | -   [--delay ms]
gbd selftest
gbd version | help
```

- In `gbd`, `batch` sends `stepDelayMs: 0` unless you pass `--delay N` or the JSON already has it.
- Windows PowerShell 5.1 strips double quotes when it calls an .exe. `gbd` tries to recover them from the raw command line, but `--b64` or `--file` is the reliable way. `-` reads the JSON from stdin.
- `gbd` has no `on`/`off` or `stop`.

The PowerShell CLI takes the same commands (`grokbot-desktop.ps1 <command>`), plus `stop`. Its `batch` keeps a 120 ms default pause between steps.

## Commands

`status`: version, `killSwitch` (on/off), port, pid, virtual screen, monitors (with DPI) and `features`. Works while off.

`screenshot`: saves an image under `%TEMP%\deskctl\shot-*.jpg|png` and returns `path`, size, `format`, `bytes`, `originX`/`originY`, `scale`, `dpiScale` and `preset`. No image data in the response.
- Light by default: the active window, JPG quality 60, at most 1280 px wide. With no usable active window (desktop or taskbar in front), the whole screen with the same settings.
- `--full` (or `"full": true`): all monitors, PNG, real size.
- `--monitor N` (0-based) or `all`, `--window active`, `--hwnd <id>`, `--max-width`, `--format`, `--quality` override the defaults.
- An image point `(px, py)` is screen point `(originX + px / scale, originY + py / scale)`. That is what `--space image` does for `click` and `move`, using the latest screenshot.

`open <app|url|uri>`: launches the target, brings its window to the front and returns `hwnd`, `title`, `process`, `match` (`host`, `changed`, `new`, `reused`, `ctrl+t`), `reused`, `newWindow`, `titleBefore`, `foreground`, `covered`, `input` and `elapsedMs`. No screenshot.
- URLs (`https://...` or a bare domain such as `x.com/home`) open as an argument to Chrome, which always makes a new tab and never types over an open one. Without Chrome, the default browser opens them.
- Shortcuts, matched by **process name** (never by window title, so they work in any Windows language): `chrome`, `edge`, `notepad`, `calc`, `paint`, `settings` (`ms-settings:`), `explorer` (class `CabinetWClass`), `word`, `excel`. Store apps are resolved from their ApplicationFrameHost frame to the real app process. `--wait <title>` matches by title instead, when you ask for it.
- URL to a running browser: done as soon as a Chrome window is in front with the host in its title or a changed title; if Chrome already showed that page, done after about 1.5 s. An app that is already open: its window is reused after 2.5 s. An unknown app with no new window fails with `no_window`.
- Bringing a window forward never clicks and never sends a real keystroke: the server attaches its own thread to the foreground thread (AttachThreadInput), calls SetForegroundWindow, retries after a TOPMOST toggle, and taps F24 (an unassigned key) first. Browser windows never get the title-bar click fallback or an Alt key.
- `chrome://`, `edge://`, `about:` pages are never passed to ShellExecute (Windows would route them elsewhere, for example `chrome://settings` to Windows Settings), and Chrome ignores `chrome://` URLs on its command line. So `open` brings the browser forward, sends Ctrl+T, checks that the same browser process is in front with a changed title (a new tab) and only then types the URL and Enter. If the new tab cannot be verified it types nothing (`new_tab_unverified`).

`type <text>`: types into the focused control.
- Space, Enter (`\n`), Tab and characters the current keyboard layout types with no modifier or with Shift are sent as real keys (with Shift when needed). Everything else (AltGr characters such as `@` on a Spanish layout, accents, emoji, letters with Caps Lock on) is sent as a Unicode key down + up pair. Never Ctrl or Alt. `\r` is ignored.
- Each character's events go in one SendInput call, 3 ms apart (`--gap 0-50`), in chunks of 32 with the kill switch checked between chunks.
- If the foreground window changes while typing, it stops at once with `focus_changed` and reports how many characters were typed.
- Never use it for passwords.

`key <combo>`: `ctrl+c`, `ctrl+s`, `ctrl+t`, `enter`, `esc`, `win+r`, `f5`... Modifiers: ctrl, alt, shift, win. Keys: a-z, 0-9, f1-f24, enter, tab, esc, space, backspace, delete, insert, home, end, pageup, pagedown, up, down, left, right, printscreen, apps.

`click`, `move`, `scroll`: virtual-screen pixels, or `--space image` for coordinates in the latest screenshot. Positive `dy` scrolls down.

`foreground`: the window in front (hwnd, title, pid, rect, `cloaked`, `covered`/`coveredBy`), without a screenshot.

`windows`: top-level windows, each with `cloaked` (hidden by Windows although listed as visible, such as the second "Calculator" window of Store apps).

`focus <title> | --hwnd <id>`: brings a window to the front and verifies with a hit test that it is really visible; otherwise `covered`. Cloaked windows are ignored; among duplicates the highest in z-order wins.

`wait --title <text>`: polls every ~100 ms until a visible window has that text in its title (`--foreground`: and is in front; `--gone`: until none is left). Default 5000 ms, max 60000; otherwise `timeout`.

`launch <program|file|uri>`: starts it as your normal user, never elevated. URIs (`ms-settings:`, `shell:AppsFolder\...`) go through ShellExecute, then `explorer.exe <uri>`. With `--wait-title`, waits for a new matching window (or an existing one that comes to the front with a new title) and returns it in `window`; if none appears, an existing matching window is brought forward with `reused: true`.

`selftest`: the post-install check, also usable as a batch step (`{"cmd":"selftest"}`).
1. `open x.com` in Chrome (must be in front, process `chrome`).
2. `open calc`; Calculator must be in front; Escape; type `2+2=`; light screenshot.
3. `open notepad`; must be process `notepad` and a **new** note: a new window, or the same Notepad window showing a different title than before the launch (a new tab), and never a title starting with `*` (unsaved changes). Otherwise it fails with `not_a_new_note` and types nothing.
4. Types the welcome note (with line breaks) into that note, only if it is still in front; light screenshot.
Returns `steps` (pass/fail, `ms`, hwnd, title, screenshot path for the calculator and note steps), `passed`, `total` and `elapsedMs`. It stops at the first failed step.

### batch (many actions in one call)

`batch` takes a JSON list of steps and runs them in order inside the server, in one HTTP call. It stops at the first failed step and returns `results` (`step`, `cmd`, `ok`, `ms` and the same fields as the single command), plus `completed` and `failedStep`.

- Commands: `screenshot`, `move`, `click`, `scroll`, `type`, `key`, `windows`, `focus`, `wait`, `launch`, `open`, `selftest`, `foreground` and `sleep` (`ms`, up to 10000). Fields are the same as each command's JSON body: `x`, `y`, `space`, `button`, `double`, `dy`, `text`, `gapMs`, `combo`, `title`, `hwnd`, `timeoutMs`, `foreground`, `gone`, `path`, `args`, `waitTitle`, `monitor`, `maxWidth`, `format`, `quality`, `window`, `full`, `target`.
- Max 100 steps and 120 s per batch. All steps are validated before any runs.
- Pause between steps: send an object instead of a list, `{"stepDelayMs": 0, "steps": [...]}` (0 = none, max 5000). Default 120 ms from the PowerShell CLI, 0 from `gbd`. The kill switch is also checked during the pause.

Example (`steps.json`): open a new Notepad window, type and take a light screenshot:

```json
[
  {"cmd":"open","target":"notepad"},
  {"cmd":"type","text":"Hello from WinDesk Bot"},
  {"cmd":"screenshot"}
]
```

```powershell
& "$env:LOCALAPPDATA\GrokBotDesktop\gbd.exe" batch --file "$env:TEMP\deskctl\steps.json"
```

### Going fast

- Use `gbd` instead of `grokbot-desktop.ps1`: no PowerShell start-up per call.
- Group actions into one `batch`.
- Open things with `open` (launch, bring to front and read the title, no screenshot).
- Verify with `foreground` or `wait`; take a screenshot only when you need to see.
- Screenshots are light by default; ask for `--full` only when you need everything.

### Autostart (optional)

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\GrokBotDesktop\scripts\register-startup.ps1"
```

Creates a **Grok Bot Desktop** shortcut in the Windows Startup folder. It always starts off until you turn it on from the tray. To remove it, uninstall or delete it from `shell:startup`.

## Uninstall

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\GrokBotDesktop\scripts\uninstall.ps1"
```

Stops the process, removes the Startup shortcut and deletes `%LOCALAPPDATA%\GrokBotDesktop` (and `%LOCALAPPDATA%\deskctl` if left over), including the token. `-KeepToken` keeps only the token.

## Troubleshooting

- `bridge_unavailable`: the server is not running. Run `scripts\start.ps1`.
- `no_token`: not installed. Run `scripts\install.ps1`.
- `kill_switch_off`: turn it on from the tray icon.
- `client_missing` (from `gbd.cmd`): `gbd.exe` is missing and could not be built. Run `scripts\build-client.ps1`, or use `grokbot-desktop.ps1`.
- `focus_failed`: Windows refused to bring the window forward (for example an elevated window). Ask the owner, or click its taskbar button after a screenshot.
- `no_window`: `open` launched the target but saw no matching window. Pass `--wait <title>` or take a screenshot.
- `new_tab_unverified`: Ctrl+T could not be verified for a `chrome://` page; nothing was typed.
- `focus_changed`: the foreground window changed while typing; typing stopped.
- `selftest_failed`: see `steps` for the step and its `error`.
- Screenshots older than 24 h are deleted from `%TEMP%\deskctl` automatically.

## Not tested on Linux

The server runs headless on Linux only for protocol tests (parsing, auth, loopback bind, kill switch). Tray, capture, mouse, keyboard, icon and window functions can only be tested on Windows.

## Do not

- Expose the port to the network.
- Share the token.
- Leave it on when you walk away from the PC.
- Run it elevated "just in case".
