#ifndef RUNNER_TITLE_BAR_H_
#define RUNNER_TITLE_BAR_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

// Lets the Dart side colour the native title bar so it matches the app
// header. Channel: "postbox/window", method "setTitleBar".
void RegisterTitleBarChannel(flutter::BinaryMessenger* messenger, HWND hwnd);

#endif  // RUNNER_TITLE_BAR_H_
