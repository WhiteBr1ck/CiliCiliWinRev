# 安装包与更新发布

更新仓库为 https://github.com/WhiteBr1ck/CiliCiliWinRev 。客户端读取公开 GitHub Releases，无需登录 GitHub。

每个正式发行版使用标签 `vX.Y.Z`，例如 `v0.6.1`。Release 附件只上传 `CiliCiliWinRev-X.Y.Z-windows-x64-setup.exe`，名称必须匹配标签中的数字版本。安装包附带播放器和所需运行库，无需便携包或单独 SHA 文件。

客户端默认在每次启动时检查一次最新稳定版。草稿、预发行版及旧版本不提示升级。若新版尚无对应安装包，设置中会显示“新版尚未提供 Windows x64 安装包”。从 0.7.0 开始，应用使用自己的 Material 3 更新弹窗，只有点击“立即更新”才下载。下载进度、取消与失败重试均在应用内完成；校验通过并保存进度后，自动退出、安装、删除安装包并重新打开。安装阶段只显示简短进度窗口。[设计依据](update-design.md)。

## 构建

先同步 `pubspec.yaml` 与 `lib/app_version.dart` 的版本，保留现有安装程序 AppId，然后执行：

```powershell
./tools/build_windows.ps1 -FlutterSdk D:/1Sync/Dev/flutter
./tools/build_installer.ps1 -Compiler "C:/Program Files/Inno Setup 7/ISCC.exe"
```

`build_windows.ps1` 完成依赖解析、静态分析、单元测试及 Release 构建。`package_windows.ps1` 校对 EXE 文件版本并打包，`build_installer.ps1` 使用 Inno Setup 7 生成安装包，构建日志记录 SHA256。默认目录为当前用户的 `%LOCALAPPDATA%/Programs/CiliCiliWinRev`，支持自选目录和覆盖升级；卸载不删除应用数据。

编译器下载：https://jrsoftware.org/isdl.php 。此项目使用 7.1.0 编译并验证，安装包含简体中文和英文界面。

## 首次发布

首次发布先将工程源码提交到仓库的 `main` 分支，随后在 GitHub Releases 中创建 `v0.6.1` 正式发行版并附带对应安装包。源码无需提交 `dist`、`build`、`.research`、原版客户端或原版安装包，这些目录已经列入 `.gitignore`。

已有 `main` 提交并明确决定发布后，可以使用 GitHub CLI：

```powershell
gh release create v0.6.1 --repo WhiteBr1ck/CiliCiliWinRev --target main --title "CiliCiliWinRev 0.6.1" --notes-file docs/release-0.6.1.md dist/CiliCiliWinRev-0.6.1-windows-x64-setup.exe
```

后续依次递增版本。当前安装的 0.6.0 遇到 0.7.0 正式发行版时会提示升级，遇到 0.6.0 或更早的版本时显示已是最新版本。网络失败和 API 限流均允许重试，不会误报为最新。

## 更新签名与索引

发布机器首次执行 `./tools/initialize_update_signing.ps1`。密钥保存在 `%LOCALAPPDATA%/CiliCiliWinRevPublisher/update-signing-key.dpapi`，使用当前用户 DPAPI 加密并限制目录 ACL。源码只提交 `lib/services/update_public_key.dart` 与 `windows/runner/update_public_key.h` 的公钥。不要重新生成密钥或替换公钥，否则已有客户端无法验证后续更新。

DPAPI 文件依赖原 Windows 用户。备份必须保留该用户，或另外安全备份私钥；直接复制 DPAPI 文件到另一台机器不能视为可恢复备份。发布脚本不会上传私钥。

每次构建后执行 `./tools/generate_update_manifest.ps1 -Installer dist/CiliCiliWinRev-0.7.0-windows-x64-setup.exe`。脚本核对安装包版本、签名并用应用公钥验证，输出 `dist/update-0.7.0.json`，包含版本、下载地址、大小、SHA256 与 Ed25519 签名。WinSparkle 的官方工具只用于发布时签名，客户端不打包其运行库。

先发布正式 Release 并核对下载内容，再将生成的文件复制至 `updates/0.7.0/windows.json` 并推送 `main`，避免索引提前指向尚不可下载的文件。客户端读取每个目标版本的 `https://raw.githubusercontent.com/WhiteBr1ck/CiliCiliWinRev/main/updates/X.Y.Z/windows.json`，避免检查版本与索引版本不同的竞态。已发布的版本索引不覆盖。

Release 仍只上传安装包，签名放在仓库更新索引中，不生成 SHA、ZIP 或额外附件。更新签名不等于 Windows Authenticode 代码签名。
