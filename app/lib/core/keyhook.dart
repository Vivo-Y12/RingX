/// Dart bridge to the runner's exported keyboard hook
/// (`ringx_hook_start` / `ringx_hook_stop` in windows/runner/keyhook.cpp).
///
/// The callback runs on the native hook thread; [NativeCallable.listener] only
/// posts an event to this isolate, so the hook never blocks on Dart code.
library;

import 'dart:async';
import 'dart:ffi';

typedef _CbC = Void Function(Uint32, Int32);
typedef _StartC = Int32 Function(Pointer<NativeFunction<_CbC>>);
typedef _StartD = int Function(Pointer<NativeFunction<_CbC>>);
typedef _StopC = Void Function();
typedef _StopD = void Function();

class RawKeyEvent {
  const RawKeyEvent(this.vk, this.down);
  final int vk;
  final bool down;
}

class KeyHook {
  NativeCallable<Void Function(Uint32, Int32)>? _callable;
  final _events = StreamController<RawKeyEvent>.broadcast();
  bool _started = false;

  /// Key events from the low-level keyboard hook, system-wide.
  Stream<RawKeyEvent> get events => _events.stream;

  /// True when this machine's runner exports the hook (Windows desktop only).
  bool get available {
    try {
      DynamicLibrary.process()
          .lookupFunction<_StartC, _StartD>('ringx_hook_start');
      return true;
    } on ArgumentError {
      return false;
    }
  }

  /// Starts the hook. Returns false when the runner does not export it.
  bool start() {
    if (_started) return true;
    final proc = DynamicLibrary.process();
    final start = proc.lookupFunction<_StartC, _StartD>('ringx_hook_start');
    _stop = proc.lookupFunction<_StopC, _StopD>('ringx_hook_stop');
    _callable = NativeCallable<Void Function(Uint32, Int32)>.listener(
        (int vk, int down) {
      if (!_events.isClosed) {
        _events.add(RawKeyEvent(vk, down != 0));
      }
    });
    if (start(_callable!.nativeFunction) != 0) {
      _callable!.close();
      _callable = null;
      return false;
    }
    _started = true;
    return true;
  }

  _StopD? _stop;

  Future<void> stop() async {
    if (!_started) return;
    _stop?.call();
    _started = false;
    // Let pending posted events drain before closing the callable.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _callable?.close();
    _callable = null;
  }

  void dispose() {
    stop();
    _events.close();
  }
}
