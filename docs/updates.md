# 安装包与更新发布

更新仓库为 https://github.com/WhiteBr1ck/CiliCiliWinRev 。客户端读取公开 GitHub Releases，无需登录 GitHub。

每个正式发行版使用标签 `vX.Y.Z`，例如 `v0.6.1`。Release 附件只上传 `CiliCiliWinRev-X.Y.Z-windows-x64-setup.exe`，名称必须匹配标签中的数字版本。安装包附带播放器和所需运行库，无需便携包或单独 SHA 文件。

客户端默认在每次启动时检查一次最新稳定版。草稿、预发行版及旧版本不提示升级。若新版尚无对应安装包，设置中会显示“新版尚未提供 Windows x64 安装包”。用户选择“下载安装包”后由默认浏览器下载，再运行安装程序覆盖升级。自动检查不等于静默安装。

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
