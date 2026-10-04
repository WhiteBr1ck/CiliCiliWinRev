// Isolated parent/installer fixture. Never loads Flutter or account data.
#include <windows.h>
#include <shellapi.h>
#include <filesystem>
#include <fstream>
#include <map>
#include <string>
#include <vector>
std::wstring Quote(const std::wstring& value) { return L"\"" + value + L"\""; }
int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  int count = 0;
  auto args = CommandLineToArgvW(GetCommandLineW(), &count);
  std::map<std::wstring, std::wstring> options;
  bool installer_mode = false;
  for (int i = 1; i < count; ++i) {
    if (args[i][0] == L'/') installer_mode = true;
    if (args[i][0] == L'-' && i + 1 < count) { auto key = args[i]; options[key] = args[++i]; }
  }
  LocalFree(args);
  std::vector<wchar_t> buffer(32768);
  GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
  const std::filesystem::path executable(buffer.data());
  if (installer_mode) return 42; // Signed/versioned failing installer fixture.
  if (options.empty()) {
    std::ofstream(executable.parent_path() / "restarted.txt") << "restarted\n";
    return 0;
  }
  const auto suffix = std::to_wstring(GetCurrentProcessId());
  const auto prefix = L"Local\\CiliCiliWinRev-test-" + suffix;
  const auto ready_name = prefix + L"-ready", commit_name = prefix + L"-commit", cancel_name = prefix + L"-cancel";
  const HANDLE ready = CreateEventW(nullptr, TRUE, FALSE, ready_name.c_str());
  const HANDLE commit = CreateEventW(nullptr, TRUE, FALSE, commit_name.c_str());
  const HANDLE cancel = CreateEventW(nullptr, TRUE, FALSE, cancel_name.c_str());
  const std::wstring helper = options[L"--helper"];
  std::wstring command = Quote(helper) + L" --parent " + suffix +
      L" --installer " + Quote(options[L"--installer"]) + L" --app " + Quote(executable.wstring()) +
      L" --ready-event " + Quote(ready_name) + L" --commit-event " + Quote(commit_name) +
      L" --cancel-event " + Quote(cancel_name) + L" --sha256 " + options[L"--sha256"] + L" --version " + options[L"--version"];
  STARTUPINFOW startup{sizeof(STARTUPINFOW)};
  PROCESS_INFORMATION process{};
  if (!CreateProcessW(helper.c_str(), command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW,
      nullptr, executable.parent_path().c_str(), &startup, &process)) return 3;
  CloseHandle(process.hThread);
  const HANDLE gates[] = {ready, process.hProcess};
  const DWORD result = WaitForMultipleObjects(2, gates, FALSE, 10000);
  std::ofstream report(options[L"--report"]);
  report << "helperPid=" << process.dwProcessId << '\n';
  if (result != WAIT_OBJECT_0) {
    DWORD code = 0; GetExitCodeProcess(process.hProcess, &code);
    report << "rejected=" << code << '\n';
    CloseHandle(process.hProcess); CloseHandle(ready); CloseHandle(commit); CloseHandle(cancel);
    return 4;
  }
  report << "ready\nfixtureSaved\n";
  const auto mode = options[L"--mode"];
  if (mode == L"commit") { SetEvent(commit); report << "committed\n"; }
  if (mode == L"cancel") { SetEvent(cancel); report << "cancelled\n"; }
  CloseHandle(process.hProcess); CloseHandle(ready); CloseHandle(commit); CloseHandle(cancel);
  return 0;
}
