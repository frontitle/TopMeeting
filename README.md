# TopMeeting

[English](README.en.md) · [贡献指南](CONTRIBUTING.md) · [架构](docs/ARCHITECTURE.md)

面向多人会议的原生 macOS 会议助手。会议录音、声纹和实录保存在本机；通过可配置的模型服务生成结构化纪要。当前开发版本 **0.13.0**，项目原创代码采用 **Apache-2.0**。

## Windows 预览版下载

[Windows x64 安装包与 ZIP](https://github.com/frontitle/TopMeeting/releases/tag/windows-v0.13.0-preview.1)。首次下载模型后可离线实时转写、自动匹配声纹。悬浮窗支持暂停和继续。飞书、钉钉、腾讯文档、Google Docs 和 Notion 可在开会时建档并提供链接。详见 [Windows 能力说明](apps/windows/README.md)。

## 当前能力

- 中英文主要界面、系统支持的会议识别语言选择，以及独立的中英文总结语言设置。
- macOS 26+ 优先使用 SpeechAnalyzer 连续本机转写；旧系统保留 Speech 框架兼容路径。语言可用性取决于系统与已安装模型。
- 系统聆听悬浮窗：拖动、双击回到主界面、暂停/继续、会议时长、动态音量波形和当前说话人。临时字幕定稿后整段进入实录。
- 会中自动发现声纹，点击说话人搜索已有人员或直接添加姓名；支持身份合并。低置信度保持未确认，重叠检测不等于重叠语音分离。
- 实录选词纠错、识别语境提示、会议 AI 对话；纠错属于上下文提示，不是重新训练模型。
- 会议按日期分组、状态筛选，以及跨标题、实录、纪要和说话人的关键词搜索；支持删除和恢复。
- 会中手动更新纪要、结束录音后完整总结；相同输入去重，不定时重复发送全量会议。当前总结请求仍使用整场快照。
- 设置中的“扩展”统一配置 OpenClaw、OpenAI-compatible 模型 API 和飞书。模型凭据分别存入钥匙串。兼容 API 通常有独立计费，不等于订阅额度。
- 飞书文档桥接支持正文、原音附件及最终画板流程；真实云端结果仍需在用户授权环境验收。

## 本地开发

需要 macOS、Swift 6 与支持 SpeechAnalyzer 的 SDK（macOS 26+）。部署最低版本为 macOS 15。现代识别路径需要受支持的设备和系统语言模型。

```sh
swift build -c release
./scripts/check.sh
node --test packages/core/test/core.test.js
```

完整开发应用打包还需要本地语音运行时与飞书 CLI：

```sh
./scripts/setup-voice.sh
./scripts/setup-feishu.sh
./scripts/build-app.sh
```

输出 `dist/TopMeeting.app`，使用本机 ad-hoc 签名。当前语音运行时依赖本机 Python 3.13 framework，尚非可直接分发到任意 Mac 的独立安装包。模型与运行时下载见脚本及第三方声明。

`check.sh` 使用本机模拟服务，不使用真实账户或消耗模型额度。界面可用隔离示例数据渲染：

```sh
./scripts/preview-workspace.sh /tmp/topmeeting-preview.png
TOPMEETING_UI_LANGUAGE=en ./scripts/preview-workspace.sh /tmp/topmeeting-english.png
```

## 服务与数据

在设置 → 扩展中填写服务地址和模型/Agent，不提供私人服务器默认地址。OpenClaw 需要启用服务端 Chat Completions HTTP 接口；客户端不包含 OpenClaw，也不读取浏览器订阅凭据。订阅可用范围由服务端账户和提供方决定。

本地数据目录为 `~/Library/Application Support/TopMeeting/`。生成总结、AI 对话时会把相关文字发往所选模型服务；启用飞书同步时会发送文档内容和所选录音。源码和 CI 不包含实际会议、声纹、账户配置或令牌。参见 [安全说明](SECURITY.md)。

## 跨平台与后续范围

现有完整客户端为 macOS；新增 [Windows 0.13.0 预览客户端](apps/windows/README.md)，支持本地流式转写、声纹和文档账号连接。`packages/core` 提供不依赖平台的搜索、转写差异与带来源校验的纪要补丁基础，配有 Windows/macOS/Linux CI 配置；尚未替代原生 Swift 业务层。扩展清单定义位于 `schemas/`。

Windows 功能补齐、Web 客户端、Slack 连接器、SQLite 全文索引和项目分类、自动增量实时总结仍是后续工作。系统音频采集、多人重叠语音分离、签名公证和自动更新也尚未实现。详见 [产品路线](docs/PRODUCT-ROADMAP.zh-CN.md)。

## 参考与许可

交互与架构参考 [Backchannel](https://github.com/talberthoule/backchannel) 和 [meeting-minutes-pro](https://github.com/JerryWoo/meeting-minutes-pro)。参考不表示将其代码或模型改授本项目许可证。

原创代码见 [LICENSE](LICENSE) 和 [NOTICE](NOTICE)；依赖、模型及参考来源见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。第三方资产遵循各自许可。
