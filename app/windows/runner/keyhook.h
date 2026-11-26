// Ringx — low-level keyboard hook (original code, BSD-3 clause LICENSE of the
// Flutter template does NOT cover this file; see LICENSE).
//
// The hook thread installs a WH_KEYBOARD_LL hook and pumps messages. Key
// events are forwarded to a Dart-provided callback via NativeCallable, which
// only posts to the Dart event loop (fast enough for the hook timeout).
//
// Exported with extern "C" + dllexport so Dart's DynamicLibrary.process()
// can resolve these symbols in the running exe.

#ifndef RUNNER_KEYHOOK_H_
#define RUNNER_KEYHOOK_H_

typedef void (*RingxKeyCallback)(unsigned int vk_code, int is_down);

// Starts the keyboard hook. Returns 0 on success, non-zero on failure.
// Idempotent: calling it while running returns 0.
extern "C" __declspec(dllexport) int ringx_hook_start(RingxKeyCallback callback);

// Stops the keyboard hook. Safe to call when not running.
extern "C" __declspec(dllexport) void ringx_hook_stop(void);

#endif  // RUNNER_KEYHOOK_H_
