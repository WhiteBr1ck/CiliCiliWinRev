#include <windows.h>
#include <shellapi.h>
#include <filesystem>
#include <string>
#include <map>
#include <vector>
#include <fstream>
#include "update_verification.h"

namespace {
void Error(const wchar_t* message) {
  MessageBoxW(nullptr, message, L"CiliCiliWinRev 更新", MB_OK | MB_ICONERROR | MB_SETFOREGROUND);
}
bool Start(const std::filesystem::path& program, std::wstring arguments,
           const std::filesystem::path& directory, bool wait, DWORD& code) {
  std::wstring command = L"\"" + program.wstring() + L"\" " + arguments;
  STARTUPINFOW startup{sizeof(STARTUPINFOW)};
  PROCESS_INFORMATION process{};
  if (!CreateProcessW(program.c_str(), command.data(), nullptr, nullptr, FALSE, 0,
      nullptr, directory.c_str(), &startup, &process)) return false;
  CloseHandle(process.hThread);
  if (wait) {
    WaitForSingleObject(process.hProcess, INFINITE);
    GetExitCodeProcess(process.hProcess, &code);
  }
  CloseHandle(process.hProcess);
  return true;
}
}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  int count = 0;
  wchar_t** arguments = CommandLineToArgvW(GetCommandLineW(), &count);
  if (!arguments || count != 17) { if (arguments) LocalFree(arguments); return 2; }
  std::map<std::wstring, std::wstring> options;
  for (int i = 1; i < count; i += 2) options[arguments[i]] = arguments[i + 1];
  LocalFree(arguments);
  const std::filesystem::path installer(options[L"--installer"]), app(options[L"--app"]);
  const auto parent_text = options[L"--parent"];
  if (parent_text.empty() || parent_text.find_first_not_of(L"0123456789") != std::wstring::npos ||
      !installer.is_absolute() || !app.is_absolute() || app.filename() != L"CiliCiliWinRev.exe") return 2;
  wchar_t* end = nullptr;
  const auto parent_id = wcstoul(parent_text.c_str(), &end, 10);
  if (!parent_id || !end || *end) return 2;
  const HANDLE parent = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, parent_id);
  if (!parent) return 3;
  // The installer must update the directory of the actual running client.
  std::vector<wchar_t> parent_path(32768);
  DWORD length = static_cast<DWORD>(parent_path.size());
  std::error_code ec;
  if (!QueryFullProcessImageNameW(parent, 0, parent_path.data(), &length) ||
      !std::filesystem::equivalent(app, std::filesystem::path(parent_path.data()), ec)) {
    CloseHandle(parent); return 3;
  }
  const HANDLE payload = CreateFileW(installer.c_str(), GENERIC_READ, FILE_SHARE_READ,
      nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  const HANDLE ready = OpenEventW(EVENT_MODIFY_STATE, FALSE, options[L"--ready-event"].c_str());
  const HANDLE commit = OpenEventW(SYNCHRONIZE, FALSE, options[L"--commit-event"].c_str());
  const HANDLE cancel = OpenEventW(SYNCHRONIZE, FALSE, options[L"--cancel-event"].c_str());
  if (payload == INVALID_HANDLE_VALUE || !ready || !commit || !cancel ||
      !VerifyPayloadHash(payload, options[L"--sha256"]) ||
      !VerifyInstallerVersion(installer.wstring(), options[L"--version"])) {
    if (payload != INVALID_HANDLE_VALUE) CloseHandle(payload);
    if (ready) CloseHandle(ready);
    if (commit) CloseHandle(commit);
    if (cancel) CloseHandle(cancel);
    CloseHandle(parent); return 4;
  }
  SetEvent(ready); CloseHandle(ready);
  // Exit alone is insufficient: the shell must explicitly confirm persistence.
  // A failed save followed by a normal close must never apply the update.
  const HANDLE gates[] = {commit, cancel, parent};
  const DWORD authorized = WaitForMultipleObjects(3, gates, FALSE, 60000);
  CloseHandle(commit);
  CloseHandle(cancel);
  if (authorized != WAIT_OBJECT_0) {
    CloseHandle(parent); CloseHandle(payload);
    DeleteFileW(installer.c_str());
    return 7;
  }
  const DWORD ended = WaitForSingleObject(parent, 60000);
  CloseHandle(parent);
  if (ended != WAIT_OBJECT_0) {
    CloseHandle(payload);
    Error(L"软件尚未退出，更新已取消。请保存播放进度后重试。");
    return 5;
  }
  const auto folder = installer.parent_path();
  const auto log = folder / L"install.log";
  std::ofstream(log, std::ios::app) << "CiliCiliWinRev installer handoff started\n";
  const auto parameters = L"/SILENT /SP- /SUPPRESSMSGBOXES /NORESTART /RESTARTEXITCODE=3010 /NOCLOSEAPPLICATIONS "
      L"/NOFORCECLOSEAPPLICATIONS /NORESTARTAPPLICATIONS /DIR=\"" + app.parent_path().wstring() +
      L"\" /LOG=\"" + log.wstring() + L"\"";
  DWORD code = 0;
  const bool installed = Start(installer, parameters, folder, true, code);
  std::ofstream(log, std::ios::app) << "installerLaunched=" << installed << " exitCode=" << code << '\n';
  CloseHandle(payload);
  if (!installed || (code != 0 && code != 3010)) {
    Error((L"更新未完成。请重试或手动安装。\n安装日志：" + log.wstring()).c_str());
  } else if (code == 3010) {
    Error(L"更新需要重启 Windows 后才能完成。请稍后重启电脑。");
  }
  if (installed && (code == 0 || code == 3010)) {
    bool deleted = false;
    for (int attempt = 0; attempt < 20; ++attempt) {
      if (DeleteFileW(installer.c_str()) || GetLastError() == ERROR_FILE_NOT_FOUND) {
        deleted = true; break;
      }
      Sleep(250);
    }
    if (!deleted) {
      Error(L"安装已完成，但无法删除下载的安装包。请稍后在缓存目录中删除。");
    }
  }
  if (code != 3010) {
    DWORD ignored = 0;
    if (!Start(app, L"", app.parent_path(), false, ignored)) {
      Error(L"无法重新打开软件，请从开始菜单启动 CiliCiliWinRev。");
    }
  }
  // A tiny batch-free cleanup process is unnecessary; logs and the helper are
  // kept for diagnosis. The OS temporary-directory policy may remove them later.
  return installed ? static_cast<int>(code) : 6;
}
