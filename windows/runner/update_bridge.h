#pragma once
#include <windows.h>
#include <string>
bool ValidateWindowsUpdate(std::string& error);
bool PrepareWindowsUpdate(const std::wstring& installer, const std::wstring& digest,
                          const std::wstring& version, std::string& error);
bool AuthorizeUpdateExit();
void CancelWindowsUpdate();
