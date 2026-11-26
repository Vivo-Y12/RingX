#include "keyhook.h"

#include <windows.h>

#include <atomic>
#include <thread>

namespace {

std::atomic<RingxKeyCallback> g_callback{nullptr};
HHOOK g_hook = nullptr;
std::thread g_thread;
std::atomic<DWORD> g_hook_thread_id{0};

// Injected events are skipped so Ringx never reacts to synthetic keystrokes
// (other tools, remote input, accessibility software).
bool IsInjected(const KBDLLHOOKSTRUCT& info) {
  return (info.flags & LLKHF_INJECTED) != 0;
}

LRESULT CALLBACK HookProc(int code, WPARAM wparam, LPARAM lparam) {
  if (code == HC_ACTION) {
    const auto* info = reinterpret_cast<const KBDLLHOOKSTRUCT*>(lparam);
    if (info != nullptr && !IsInjected(*info)) {
      const bool is_down = (wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN);
      RingxKeyCallback cb = g_callback.load(std::memory_order_relaxed);
      if (cb != nullptr) {
        cb(info->vkCode, is_down ? 1 : 0);
      }
    }
  }
  return CallNextHookEx(nullptr, code, wparam, lparam);
}

void HookThreadMain() {
  g_hook_thread_id.store(GetCurrentThreadId(), std::memory_order_release);
  g_hook = SetWindowsHookExW(WH_KEYBOARD_LL, HookProc,
                             GetModuleHandleW(nullptr), 0);
  MSG msg;
  // GetMessage returns 0 on WM_QUIT and -1 on error; both end the pump.
  while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }
  if (g_hook != nullptr) {
    UnhookWindowsHookEx(g_hook);
    g_hook = nullptr;
  }
  g_hook_thread_id.store(0, std::memory_order_release);
}

}  // namespace

int ringx_hook_start(RingxKeyCallback callback) {
  g_callback.store(callback, std::memory_order_release);
  if (g_hook_thread_id.load(std::memory_order_acquire) != 0) {
    return 0;  // already running; the new callback was swapped in above
  }
  g_thread = std::thread(HookThreadMain);
  // shortcut: spin briefly so callers know the hook is live before returning
  for (int i = 0; i < 100 && g_hook_thread_id.load() == 0; ++i) {
    Sleep(1);
  }
  return g_hook_thread_id.load() != 0 ? 0 : -1;
}

void ringx_hook_stop(void) {
  if (g_hook_thread_id.load(std::memory_order_acquire) != 0) {
    PostThreadMessageW(g_hook_thread_id.load(), WM_QUIT, 0, 0);
    if (g_thread.joinable()) {
      g_thread.join();
    }
  }
  g_callback.store(nullptr, std::memory_order_release);
}
