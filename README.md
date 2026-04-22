# VoiceBar

macOS 菜单栏语音输入应用。按住触发键说话，松开后自动将转写文字粘贴到任意输入框。

## 功能

- **按住说话** — 按住 Right ⌘（或 Fn / Right ⌥），对着麦克风说话
- **实时转写** — 底部 HUD 面板实时显示转写进度
- **自动粘贴** — 松开触发键后，转写文字自动粘贴到光标所在位置
- **LLM 优化** — 可选 LLM 后处理，自动修正中文同音错字（如"弟"→"的"，"配森"→"Python"）
- **多语言** — 支持简体中文、英语、繁体中文、日语、韩语
- **菜单栏常驻** — 系统菜单栏图标，不占 Dock

## 系统要求

- macOS 12.0 (Monterey) 及以上
- 麦克风权限（首次启动时弹窗请求）
- 语音识别权限（首次启动时弹窗请求）
- **输入监控权限**（System Settings → Privacy & Security → Input Monitoring → 启用 VoiceBar）

## 触发键

推荐使用 **Right ⌘**（Right Command），不和输入法快捷键冲突。可选：Right ⌥、Fn。

> ⚠️ 某些键盘（Touch Bar MacBook）的 Fn 键行为可能不同，建议用 Right ⌘。

## 构建

```bash
# macOS 上需要 Xcode 命令行工具
git clone https://github.com/soroyue/VoiceBar.git
cd VoiceBar
open VoiceBar.xcodeproj
# 在 Xcode 中：Product → Build (⌘B)
# 运行：Product → Run (⌘R)
```

## 权限说明

VoiceBar 需要以下系统权限：

| 权限 | 用途 | 设置位置 |
|------|------|----------|
| 麦克风 | 录制音频 | System Settings → Privacy & Security → Microphone |
| 语音识别 | 本地语音转文字 | System Settings → Privacy & Security → Speech Recognition |
| 输入监控 | 监听触发键 | System Settings → Privacy & Security → Input Monitoring |

## 技术原理

- **语音识别** — Apple `SFSpeechRecognizer`（设备端，无需联网）
- **键盘监控** — IOKit HID + CGEvent tap 双通道，低延迟触发键检测
- **文字粘贴** — CGEvent 模拟 Cmd+V，使用 `.hidSystemState` + `.cgAnnotatedSessionEventTap`（参考 StreamDictate）
- **HUD 面板** — SwiftUI + NSPanel（`.nonactivatingPanel`，不抢夺焦点）

### 核心参考项目

- [StreamDictate](https://github.com/thesoulpole/StreamDictate) — `.cgAnnotatedSessionEventTap` 文本注入方案
- [VoiceInput-Patch](https://github.com/BigKunLun/VoiceInput-Patch) — CGEvent 批量 UTF-16 粘贴方案

## License

MIT
