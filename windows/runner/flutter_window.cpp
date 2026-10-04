#include "flutter_window.h"

#include <optional>
#include <wincrypt.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "update_bridge.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  update_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "CiliCiliWinRev/updater",
      &flutter::StandardMethodCodec::GetInstance());
  update_channel_->SetMethodCallHandler([this](
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (call.method_name() == "validate") {
      std::string error;
      if (ValidateWindowsUpdate(error)) result->Success();
      else result->Error("UPDATE", error);
    } else if (call.method_name() == "prepare") {
      const auto* values = call.arguments() ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
      const auto get = [values](const char* name) -> std::wstring {
        if (!values) return L"";
        const auto found = values->find(flutter::EncodableValue(name));
        if (found == values->end()) return L"";
        const auto* value = std::get_if<std::string>(&found->second);
        if (!value) return L"";
        const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value->data(), static_cast<int>(value->size()), nullptr, 0);
        std::wstring wide(length, 0);
        if (length) MultiByteToWideChar(CP_UTF8, 0, value->data(), static_cast<int>(value->size()), wide.data(), length);
        return wide;
      };
      std::string error;
      if (PrepareWindowsUpdate(get("installer"), get("sha256"), get("version"), error)) result->Success();
      else result->Error("UPDATE", error);
    } else if (call.method_name() == "commit") {
      if (AuthorizeUpdateExit()) result->Success();
      else result->Error("UPDATE", "更新安装已取消，请重试");
    } else if (call.method_name() == "cancel") {
      CancelWindowsUpdate(); result->Success();
    } else result->NotImplemented();
  });
  session_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "CiliCiliWinRev/session",
      &flutter::StandardMethodCodec::GetInstance());
  session_channel_->SetMethodCallHandler([](
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (call.method_name() != "protect" && call.method_name() != "unprotect") {
      result->NotImplemented();
      return;
    }
    const auto* bytes = call.arguments() ? std::get_if<std::vector<uint8_t>>(call.arguments()) : nullptr;
    if (!bytes || bytes->empty() || bytes->size() > 65536) {
      result->Error("DPAPI", "Invalid session data");
      return;
    }
    DATA_BLOB input{static_cast<DWORD>(bytes->size()), const_cast<BYTE*>(bytes->data())};
    DATA_BLOB output{};
    const BOOL ok = call.method_name() == "protect"
        ? CryptProtectData(&input, L"CiliCiliWinRev", nullptr, nullptr, nullptr,
                           CRYPTPROTECT_UI_FORBIDDEN, &output)
        : CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr,
                             CRYPTPROTECT_UI_FORBIDDEN, &output);
    if (!ok) {
      result->Error("DPAPI", "Windows could not protect or read the session");
      return;
    }
    std::vector<uint8_t> value(output.pbData, output.pbData + output.cbData);
    SecureZeroMemory(output.pbData, output.cbData);
    LocalFree(output.pbData);
    result->Success(flutter::EncodableValue(std::move(value)));
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "CiliCiliWinRev/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler([this](
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (call.method_name() == "setFullscreen") {
      const auto* enabled = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
      if (!enabled) { result->Error("WINDOW", "Expected boolean"); return; }
      SetFullscreen(*enabled);
      result->Success();
    } else if (call.method_name() == "geometry") {
      RECT window{}, client{};
      MONITORINFO monitor{sizeof(MONITORINFO)};
      GetWindowRect(GetHandle(), &window);
      GetClientRect(GetHandle(), &client);
      GetMonitorInfo(MonitorFromWindow(GetHandle(), MONITOR_DEFAULTTONEAREST), &monitor);
      flutter::EncodableMap values;
      const auto put = [&values](const char* key, int value) {
        values[flutter::EncodableValue(key)] = flutter::EncodableValue(value);
      };
      put("left", window.left); put("top", window.top);
      put("width", window.right - window.left); put("height", window.bottom - window.top);
      put("clientWidth", client.right); put("clientHeight", client.bottom);
      put("monitorLeft", monitor.rcMonitor.left); put("monitorTop", monitor.rcMonitor.top);
      put("monitorWidth", monitor.rcMonitor.right - monitor.rcMonitor.left);
      put("monitorHeight", monitor.rcMonitor.bottom - monitor.rcMonitor.top);
      values[flutter::EncodableValue("fullscreen")] = flutter::EncodableValue(fullscreen_);
      result->Success(flutter::EncodableValue(values));
    } else if (call.method_name() == "exitApplication") {
      // Dart calls this only after preferences and the progress outbox are saved.
      // WM_QUIT destroys Flutter synchronously while video callbacks may still
      // be running. End the process without entering that teardown race.
      result->Success();
      PostMessage(GetHandle(), WM_APP + 0x61, 0, 0);
    } else { result->NotImplemented(); }
  });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  CancelWindowsUpdate();
  update_channel_ = nullptr;
  window_channel_ = nullptr;
  session_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_APP + 0x61) {
    ExitProcess(EXIT_SUCCESS);
  }
  if (fullscreen_ && message == WM_NCCALCSIZE && wparam) return 0;
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::SetFullscreen(bool enabled) {
  if (enabled == fullscreen_) return;
  const HWND hwnd = GetHandle();
  if (enabled) {
    saved_style_ = GetWindowLongPtr(hwnd, GWL_STYLE);
    saved_ex_style_ = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
    saved_placement_.length = sizeof(WINDOWPLACEMENT);
    GetWindowPlacement(hwnd, &saved_placement_);
    MONITORINFO monitor{sizeof(MONITORINFO)};
    GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), &monitor);
    fullscreen_ = true;
    ShowWindow(hwnd, SW_RESTORE);
    SetWindowLongPtr(hwnd, GWL_STYLE, (saved_style_ & ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZE | WS_MAXIMIZE | WS_MAXIMIZEBOX | WS_MINIMIZEBOX)) | WS_POPUP);
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, saved_ex_style_ & ~(WS_EX_WINDOWEDGE | WS_EX_CLIENTEDGE));
    SetWindowPos(hwnd, HWND_TOP, monitor.rcMonitor.left, monitor.rcMonitor.top,
                 monitor.rcMonitor.right - monitor.rcMonitor.left,
                 monitor.rcMonitor.bottom - monitor.rcMonitor.top,
                 SWP_FRAMECHANGED | SWP_NOOWNERZORDER);
  } else {
    fullscreen_ = false;
    SetWindowLongPtr(hwnd, GWL_STYLE, saved_style_);
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, saved_ex_style_);
    SetWindowPlacement(hwnd, &saved_placement_);
    SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED | SWP_NOOWNERZORDER);
  }
  RECT client{};
  GetClientRect(hwnd, &client);
  MoveWindow(flutter_controller_->view()->GetNativeWindow(), 0, 0,
             client.right, client.bottom, TRUE);
  flutter_controller_->ForceRedraw();
}
