# Windows 更新方案

核对日期：2026-10-04。

采用应用内下载、签名校验、独立安装交接程序与现有 Inno Setup 7 安装包。Flutter 使用自己的 Material 3 更新弹窗；下载必须由用户点击“立即更新”触发，之后自动完成保存、退出、安装、删除下载包和重启。整个正常流程只有一次确认。

## 选型

| 方案 | 已核实的行为 | 对本项目的影响 |
| --- | --- | --- |
| VS Code Windows | 下载缓存、核对 SHA256、调用 Inno Setup、独立更新进程 | 沿用 Inno Setup 是成熟软件采用的路线 |
| Electron autoUpdater | Windows 支持 Squirrel.Windows 与 MSIX，提供 quitAndInstall | 本项目不是 Electron，不能直接使用该 API |
| WinSparkle | 下载进度、取消、稍后提醒、Ed25519 签名、安装回调，支持 Inno Setup | 其原生弹窗不符合当前 Material 3 流程；只使用官方签名工具 |
| Velopack | 安装程序、完整更新包、增量包和更新索引 | 更换分发体系并额外提供更新包，目前不采用 |
| MSIX App Installer | Windows 管理安装、检查更新与修复 | 更换安装格式、证书与迁移方案，目前不采用 |

没有一个适用于全部 Windows 软件的统一更新框架。共同模式是检查、下载、验证、准备重启、独立安装，再启动新版。

## 流程

1. 启动时检查公开 GitHub Releases。关闭自动检查后不执行启动检查；播放器打开时推迟更新提示。
2. 提示时只获取公开 Release 信息。用户点击“立即更新”后，读取该版本的 HTTPS 仓库文件 `updates/X.Y.Z/windows.json`，核对版本、地址与大小，然后在应用内流式下载安装包到唯一临时目录。下载支持取消、超时与重试，不附带账号凭据。
3. 在后台 isolate 核对 SHA256，并用应用内固定的 Ed25519 公钥验证完整安装包。缺少签名或错误签名不能进入安装准备阶段。SHA256 本身不能替代来源签名。
4. 将独立安装交接程序复制到安装包旁。交接程序锁定文件、重新核对 SHA256 和 EXE 版本，避免校验后被替换，也拒绝将签名有效的旧包作为新版安装。
5. 客户端保存本地历史及账号待同步记录，明确授权安装，再退出。保存失败不授权；普通关闭不能代替授权。
6. 独立进程等待客户端确实退出，调用 Inno Setup `/SILENT /SP- /NORESTART /NOCLOSEAPPLICATIONS /NOFORCECLOSEAPPLICATIONS /NORESTARTAPPLICATIONS`，传入实际安装目录。显示安装进度及错误，不强制结束其他进程。
7. 安装成功后删除下载的安装包，再从相同目录启动新版。失败显示错误并保留安装包和日志，尝试重新打开已有客户端；这不等于自动回滚。若安装程序返回需要重启 Windows，则提示重启，不立即启动程序。

自动更新只支持已登记的当前用户安装。开发构建或直接复制的目录提示先安装，可以通过设置中的 GitHub Releases 入口获取安装包。第一版带自动安装流程的 0.7.0 客户端仍需下载安装一次。辅助进程使用静态 CRT，在安装目录被覆盖时仍可运行。

下载完整安装包，没有承诺增量更新、断点续传、自动回滚或强制后台重启。更新签名与 Windows Authenticode 代码签名是不同机制，目前没有 Authenticode 证书。

## 官方依据

* [VS Code Windows 更新实现，固定提交](https://github.com/microsoft/vscode/blob/4a86ed331f5433b773e307408ad05cee9fa12985/src/vs/platform/update/electron-main/updateService.win32.ts)
* [WinSparkle 集成指南](https://winsparkle.org/guides/integrating-winsparkle/)
* [WinSparkle 发布指南及 Inno Setup 参数](https://winsparkle.org/guides/publishing-updates/)
* [WinSparkle 签名说明，固定提交](https://github.com/vslavik/winsparkle/blob/0828b4fda11230907b65c48902ab6b3a2681a7ca/README.md#signing-updates)
* [Flutter auto_updater 当前构建文件，仍捆绑 WinSparkle 0.8.1](https://github.com/leanflutter/auto_updater/blob/93fee1d1726e016359c6d621c9612f42a1c6ce38/packages/auto_updater_windows/windows/CMakeLists.txt)
* [Electron autoUpdater](https://www.electronjs.org/docs/latest/api/auto-updater)
* [Velopack 官方说明](https://github.com/velopack/velopack/blob/92d6a1c91716729d449034df5c50307dcce39493/README.md)
* [Microsoft App Installer 自动更新](https://learn.microsoft.com/en-us/windows/msix/app-installer/auto-update-and-repair--overview)
* [Inno Setup 参数](https://jrsoftware.org/ishelp/topic_setupcmdline.htm)
