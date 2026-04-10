# 🌐 ProxyToggle

> Native macOS menu bar proxy manager. Zero dependencies. Pure Swift.

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-12%2B-blue.svg)](https://developer.apple.com/macos)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/sla/proxy-toggle.svg)](https://github.com/sla/proxy-toggle/stargazers)

## Features

- 🔌 **System proxy control** — toggle HTTP/HTTPS proxy for all network interfaces
- 🌍 **Health checks** — auto-detect country, city & latency via ipinfo.io
- 🏳️ **Country flags** — beautiful flag display for 25+ countries
- ⚡ **Zero dependencies** — compiled Swift binary, no Python, no pip, no brew deps
- 📋 **Add proxies on the fly** — format: `name | host:port:user:password`
- 🔄 **Auto-sync** — keeps your trading bots & other tools in sync
- 🔔 **Native notifications** — macOS notification center on switch/add/remove
- 🚀 **Auto-start** — runs at login via LaunchAgent

## Screenshot

```
🌐 Brazil Proxy
├── ● 🟢 1208ms  🇧🇷 BR São Paulo    ← active
├── ○ ⏳          🇺🇸 US New York     ← other proxy
├── 🔌  Proxy OFF
├── 🔄  Refresh
├── ➕  Add Proxy...
├── 🗑️  Remove
└── 🚪  Quit
```

## Install

### Option 1: Download binary
```bash
# Download the latest release
curl -LO https://github.com/sla/proxy-toggle/releases/latest/download/ProxyToggle.app.zip
unzip ProxyToggle.app.zip
mv ProxyToggle.app /Applications/
open /Applications/ProxyToggle.app
```

### Option 2: Build from source
```bash
git clone https://github.com/sla/proxy-toggle.git
cd proxy-toggle
swiftc -o ProxyToggle.app/Contents/MacOS/ProxyToggle main.swift \
  -framework AppKit -framework Foundation -framework UserNotifications
mv ProxyToggle.app /Applications/
```

### Option 3: Homebrew (coming soon)
```bash
brew install --cask proxy-toggle
```

## Usage

Click the 🌐 icon in your menu bar:

| Action | Description |
|--------|-------------|
| **Click proxy** | Switch & activate |
| **🔌 Proxy OFF** | Disable system proxy |
| **🔄 Refresh** | Re-check all proxy health |
| **➕ Add Proxy** | Add new proxy (format: `name \| host:port:user:password`) |
| **🗑️ Remove** | Delete a proxy |
| **ℹ️ Info** | View proxy details (IP, country) |
| **🚪 Quit** | Close the app |

## Config

ProxyToggle stores config at `~/.proxyctl/config.json`:

```json
{
  "proxies": [
    {
      "name": "MyProxy",
      "host": "proxy.example.com",
      "port": 8080,
      "user": "username",
      "pass": "password"
    }
  ],
  "active": 0
}
```

## Why Swift?

The previous version was Python-based and had several issues:
- ❌ Heavy dependencies (rumps, httpx, typer, rich)
- ❌ Python environment issues (venv, pip, proxy blocking pip)
- ❌ Memory leaks from long-running Python processes
- ❌ Stale .pyc cache issues
- ❌ 400+ hours uptime causing connection drops

The Swift version:
- ✅ ~5MB compiled binary
- ✅ Zero runtime dependencies
- ✅ No package managers, no virtualenvs
- ✅ Native AppKit menu bar
- ✅ Instant launch on login

## License

[MIT](LICENSE)

## Author

Made with ❤️ for macOS
