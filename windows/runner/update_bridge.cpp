#include "update_bridge.h"
#include <filesystem>
#include <vector>
#include <regex>

namespace {
HANDLE update_commit = nullptr, update_cancel = nullptr, update_process = nullptr;
std::wstring ModulePath() {
  std::vector<wchar_t> buffer(32768);
  const DWORD size = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
  return size && size < buffer.size() ? std::wstring(buffer.data(), size) : L"";
}
bool InstalledHere(const std::filesystem::path& directory) {
  constexpr auto key = L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{35D7C36E-596C-4DF5-95E3-C528CD74A04B}_is1";
  std::vector<wchar_t> value(32768);
  DWORD size = static_cast<DWORD>(value.size() * sizeof(wchar_t));
  if (RegGetValueW(HKEY_CURRENT_USER, key, L"InstallLocation", RRF_RT_REG_SZ,
                  nullptr, value.data(), &size) != ERROR_SUCCESS) return false;
  std::error_code ec;
  return std::filesystem::equivalent(directory, std::filesystem::path(value.data()), ec) &&
      std::filesystem::exists(directory / L"unins000.exe", ec);
}
void ReleaseHandles() {
  for (HANDLE* handle : {&update_commit, &update_cancel, &update_process}) {
    if (*handle) CloseHandle(*handle);
    *handle = nullptr;
  }
}
}
bool ValidateWindowsUpdate(std::string& error) {
  const auto app = std::filesystem::path(ModulePath());
  if (app.empty() || !InstalledHere(app.parent_path())) {
    error = "请先安装 CiliCiliWinRev，再使用自动更新"; return false;
  }
  std::error_code ec;
  if (!std::filesystem::exists(app.parent_path() / L"CiliCiliWinRevUpdater.exe", ec)) {
    error = "更新程序缺失，请手动重新安装"; return false;
  }
  return true;
}
bool PrepareWindowsUpdate(const std::wstring& installer, const std::wstring& digest,
                          const std::wstring& version, std::string& error) {
  if (!ValidateWindowsUpdate(error)) return false;
  if (update_process && WaitForSingleObject(update_process, 0) == WAIT_TIMEOUT) {
    error = "更新程序正在准备，请稍后重试"; return false;
  }
  ReleaseHandles();
  const auto app = std::filesystem::path(ModulePath());
  const auto payload = std::filesystem::path(installer);
  std::error_code ec;
  if (!payload.is_absolute() || payload.filename() != L"setup.exe" ||
      !std::filesystem::is_regular_file(payload, ec) ||
      !std::regex_match(digest, std::wregex(L"[a-f0-9]{64}")) ||
      !std::regex_match(version, std::wregex(L"[0-9]{1,5}\\.[0-9]{1,5}\\.[0-9]{1,5}"))) {
    error = "安装包无效，请重新下载"; return false;
  }
  const auto folder = payload.parent_path(), helper = folder / L"CiliCiliWinRevUpdater.exe";
  if (!CopyFileW((app.parent_path() / L"CiliCiliWinRevUpdater.exe").c_str(), helper.c_str(), TRUE)) {
    error = "无法准备安装程序，请重试"; return false;
  }
  const auto event_name = L"Local\\CiliCiliWinRev-update-" + std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64());
  const auto commit_name = event_name + L"-commit", cancel_name = event_name + L"-cancel";
  const HANDLE ready = CreateEventW(nullptr, TRUE, FALSE, event_name.c_str());
  update_commit = CreateEventW(nullptr, TRUE, FALSE, commit_name.c_str());
  update_cancel = CreateEventW(nullptr, TRUE, FALSE, cancel_name.c_str());
  if (!ready || !update_commit || !update_cancel) {
    if (ready) CloseHandle(ready);
    ReleaseHandles(); error = "无法准备更新，请重试"; return false;
  }
  std::wstring command = L"\"" + helper.wstring() + L"\" --parent " + std::to_wstring(GetCurrentProcessId()) +
      L" --installer \"" + payload.wstring() + L"\" --app \"" + app.wstring() +
      L"\" --ready-event \"" + event_name + L"\" --commit-event \"" + commit_name +
      L"\" --cancel-event \"" + cancel_name + L"\" --sha256 " + digest + L" --version " + version;
  STARTUPINFOW startup{sizeof(STARTUPINFOW)};
  PROCESS_INFORMATION process{};
  const BOOL launched = CreateProcessW(helper.c_str(), command.data(), nullptr, nullptr,
      FALSE, CREATE_NO_WINDOW, nullptr, folder.c_str(), &startup, &process);
  if (launched) { CloseHandle(process.hThread); update_process = process.hProcess; }
  const HANDLE gates[] = {ready, update_process};
  const bool accepted = launched && WaitForMultipleObjects(2, gates, FALSE, 10000) == WAIT_OBJECT_0;
  CloseHandle(ready);
  if (!accepted) { CancelWindowsUpdate(); error = "安装包验证或安装准备失败，请重试"; return false; }
  return true;
}
bool AuthorizeUpdateExit() {
  if (!update_commit || !update_process || WaitForSingleObject(update_process, 0) != WAIT_TIMEOUT) return false;
  const BOOL authorized = SetEvent(update_commit);
  if (authorized) ReleaseHandles();
  return authorized != FALSE;
}
void CancelWindowsUpdate() {
  if (update_cancel) SetEvent(update_cancel);
  if (update_commit) { CloseHandle(update_commit); update_commit = nullptr; }
  if (update_cancel) { CloseHandle(update_cancel); update_cancel = nullptr; }
}
