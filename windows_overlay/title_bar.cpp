#include "title_bar.h"

#include <dwmapi.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

// Windows 11 (build 22000+) colours the caption and border. On Windows 10 the
// colour calls are ignored and only the dark/light switch applies.
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif
static const DWORD kBorderColor = 34;
static const DWORD kCaptionColor = 35;
static const DWORD kTextColor = 36;

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

bool ReadInt(const EncodableMap& map, const char* key, int64_t* out) {
  auto it = map.find(EncodableValue(std::string(key)));
  if (it == map.end()) return false;
  if (const auto* v = std::get_if<int32_t>(&it->second)) {
    *out = *v;
    return true;
  }
  if (const auto* v = std::get_if<int64_t>(&it->second)) {
    *out = *v;
    return true;
  }
  return false;
}

std::unique_ptr<flutter::MethodChannel<EncodableValue>> g_channel;

}  // namespace

void RegisterTitleBarChannel(flutter::BinaryMessenger* messenger, HWND hwnd) {
  g_channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "postbox/window", &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler(
      [hwnd](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() != "setTitleBar") {
          result->NotImplemented();
          return;
        }
        const auto* args = std::get_if<EncodableMap>(call.arguments());
        if (args == nullptr) {
          result->Error("bad-args", "Expected a map");
          return;
        }
        int64_t value = 0;
        auto dark_it = args->find(EncodableValue(std::string("dark")));
        if (dark_it != args->end()) {
          if (const auto* b = std::get_if<bool>(&dark_it->second)) {
            BOOL dark = *b ? TRUE : FALSE;
            DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark,
                                  sizeof(dark));
          }
        }
        // Values are COLORREF (0x00BBGGRR), converted on the Dart side.
        if (ReadInt(*args, "background", &value)) {
          COLORREF c = static_cast<COLORREF>(value);
          DwmSetWindowAttribute(hwnd, kCaptionColor, &c, sizeof(c));
        }
        if (ReadInt(*args, "text", &value)) {
          COLORREF c = static_cast<COLORREF>(value);
          DwmSetWindowAttribute(hwnd, kTextColor, &c, sizeof(c));
        }
        if (ReadInt(*args, "border", &value)) {
          COLORREF c = static_cast<COLORREF>(value);
          DwmSetWindowAttribute(hwnd, kBorderColor, &c, sizeof(c));
        }
        result->Success();
      });
}
