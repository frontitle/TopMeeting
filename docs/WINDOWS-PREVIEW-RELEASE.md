Windows x64 预览版 / Windows x64 preview

下载 `TopMeeting-0.12.0-windows-x64-setup.exe` 安装；也可解压 ZIP，运行其中的 `TopMeeting.exe`。校验值见 `SHA256SUMS.txt`。

已实现：麦克风录音、暂停/继续、原音播放、本地会议保存、搜索、实录与姓名编辑、删除恢复、Markdown 导出、OpenClaw 与兼容模型服务的流式总结。相同会议内容不重复总结，模型输出中断时保留旧纪要。

语音转写为会后手动触发，需独立配置兼容 `audio/transcriptions` 的服务；会上传选中会议尚未转写的录音，每段上限 25 MB，服务可能独立计费。

此版本尚未移植 Mac 的本机实时转写、自动声纹识别、系统聆听浮窗、飞书和完整中英文界面。Mac 原生版源代码保留在同一仓库。两个客户端的数据暂不自动同步。

验证：Windows GitHub Actions 构建；打包后的 EXE 启动、渲染界面、保存/编辑/删除/恢复会议和音频写入/读取检查；模型 URL、会话隔离、摘要去重及 SSE 截断回归。未进行真实麦克风、真实 AI 账号或实际 Windows 桌面人工验收。

安装包尚未购买/配置代码签名证书，Windows 可能提示未知发布者。原创源码采用 Apache-2.0，第三方依赖遵循各自许可。

构建来源：[Windows CI #41824680503](https://github.com/frontitle/TopMeeting/actions/runs/41824680503)，源码提交 `570d77d`。Portable core 的 Windows/macOS/Linux 检查均通过。
