#pragma once
#include <windows.h>
#include <bcrypt.h>
#include <string>
#include <vector>
inline bool VerifyPayloadHash(HANDLE file, const std::wstring& expected) {
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  BCRYPT_HASH_HANDLE hash = nullptr;
  bool ok = BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) >= 0;
  DWORD object_size = 0, copied = 0;
  if (ok) ok = BCryptGetProperty(algorithm, BCRYPT_OBJECT_LENGTH,
      reinterpret_cast<PUCHAR>(&object_size), sizeof(object_size), &copied, 0) >= 0;
  std::vector<UCHAR> object(object_size), buffer(65536), digest(32);
  if (ok) ok = BCryptCreateHash(algorithm, &hash, object.data(), object_size, nullptr, 0, 0) >= 0;
  LARGE_INTEGER beginning{};
  if (ok) ok = SetFilePointerEx(file, beginning, nullptr, FILE_BEGIN) != FALSE;
  while (ok) {
    DWORD received = 0;
    if (!ReadFile(file, buffer.data(), static_cast<DWORD>(buffer.size()), &received, nullptr)) { ok = false; break; }
    if (!received) break;
    ok = BCryptHashData(hash, buffer.data(), received, 0) >= 0;
  }
  if (ok) ok = BCryptFinishHash(hash, digest.data(), static_cast<ULONG>(digest.size()), 0) >= 0;
  if (hash) BCryptDestroyHash(hash);
  if (algorithm) BCryptCloseAlgorithmProvider(algorithm, 0);
  std::wstring actual;
  constexpr wchar_t hex[] = L"0123456789abcdef";
  for (UCHAR value : digest) { actual += hex[value >> 4]; actual += hex[value & 15]; }
  return ok && actual == expected;
}
inline bool VerifyInstallerVersion(const std::wstring& path, const std::wstring& expected) {
  DWORD ignored = 0;
  const DWORD length = GetFileVersionInfoSizeW(path.c_str(), &ignored);
  if (!length) return false;
  std::vector<UCHAR> data(length);
  if (!GetFileVersionInfoW(path.c_str(), 0, length, data.data())) return false;
  VS_FIXEDFILEINFO* info = nullptr;
  UINT size = 0;
  if (!VerQueryValueW(data.data(), L"\\", reinterpret_cast<void**>(&info), &size) ||
      size < sizeof(VS_FIXEDFILEINFO) || info->dwSignature != 0xfeef04bd) return false;
  const auto version = std::to_wstring(HIWORD(info->dwFileVersionMS)) + L"." +
      std::to_wstring(LOWORD(info->dwFileVersionMS)) + L"." + std::to_wstring(HIWORD(info->dwFileVersionLS));
  return version == expected;
}
