/// FFI bridge to vJoyInterface.dll (vJoy virtual joystick driver, public SDK
/// API — signatures verified against shauleiz/vJoy inc/vjoyinterface.h).
///
/// All calls are optional at runtime: when the vJoy driver is not installed,
/// [Vjoy.tryOpen] returns null and the app keeps running in "no device" mode.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart' show calloc;

/// vJoy axis HID usages (from the vJoy SDK public.h).
const int hidUsageX = 0x30;
const int hidUsageY = 0x31;
const int hidUsageZ = 0x32;
const int hidUsageRx = 0x33;
const int hidUsageRy = 0x34;
const int hidUsageRz = 0x35;
const int hidUsageSl0 = 0x36;
const int hidUsageSl1 = 0x37;
const int hidUsageWhl = 0x38;

/// `enum VjdStat` from vjoyinterface.h.
enum VjdStat { own, free, busy, miss, unkn }

const String _dllName = 'vJoyInterface.dll';

typedef _BoolFn = Int32 Function();
typedef _BoolFnU = Int32 Function(Uint32);
typedef _SetAxisC = Int32 Function(Int32, Uint32, Uint32);
typedef _SetBtnC = Int32 Function(Int32, Uint32, Uint8);
typedef _AxisLimC = Int32 Function(Uint32, Uint32, Pointer<Int32>);
typedef _VersionC = Int16 Function();
typedef _DriverMatchC = Int32 Function(Pointer<Uint16>, Pointer<Uint16>);

/// A live handle to vJoyInterface.dll.
class Vjoy {
  final DynamicLibrary _lib;
  Vjoy._(this._lib);

  /// Returns null when the DLL (or the driver) is not present.
  static Vjoy? tryOpen() {
    try {
      return Vjoy._(DynamicLibrary.open(_dllName));
    } on ArgumentError {
      return null;
    }
  }

  late final int Function() _enabled =
      _lib.lookupFunction<_BoolFn, int Function()>('vJoyEnabled');
  late final int Function() _version =
      _lib.lookupFunction<_VersionC, int Function()>('GetvJoyVersion');
  late final int Function(int) _status =
      _lib.lookupFunction<_BoolFnU, int Function(int)>('GetVJDStatus');
  late final int Function(int) _acquire =
      _lib.lookupFunction<_BoolFnU, int Function(int)>('AcquireVJD');
  late final void Function(int) _relinquish =
      _lib.lookupFunction<Void Function(Uint32), void Function(int)>(
          'RelinquishVJD');
  late final int Function(int) _reset =
      _lib.lookupFunction<_BoolFnU, int Function(int)>('ResetVJD');
  late final int Function(int, int, int) _setAxis =
      _lib.lookupFunction<_SetAxisC, int Function(int, int, int)>('SetAxis');
  late final int Function(int, int, int) _setBtn =
      _lib.lookupFunction<_SetBtnC, int Function(int, int, int)>('SetBtn');
  late final int Function(int) _exists =
      _lib.lookupFunction<_BoolFnU, int Function(int)>('isVJDExists');
  late final int Function(int, int) _axisExists =
      _lib.lookupFunction<_BoolFnU, int Function(int, int)>('GetVJDAxisExist');
  late final int Function(int, int, Pointer<Int32>) _axisMax =
      _lib.lookupFunction<_AxisLimC, int Function(int, int, Pointer<Int32>)>(
          'GetVJDAxisMax');
  late final int Function(int, int, Pointer<Int32>) _axisMin =
      _lib.lookupFunction<_AxisLimC, int Function(int, int, Pointer<Int32>)>(
          'GetVJDAxisMin');
  late final int Function(int) _buttonCount =
      _lib.lookupFunction<_BoolFnU, int Function(int)>('GetVJDButtonNumber');
  late final int Function(Pointer<Uint16>, Pointer<Uint16>) _driverMatch =
      _lib.lookupFunction<_DriverMatchC,
          int Function(Pointer<Uint16>, Pointer<Uint16>)>('DriverMatch');

  bool get driverEnabled => _enabled() != 0;

  /// vJoy interface version, 0 when the driver is not enabled.
  int get driverVersion => driverEnabled ? _version() : 0;

  /// True when the interface DLL and driver versions match.
  bool get driverMatches {
    if (!driverEnabled) return false;
    final dll = calloc<Uint16>();
    final drv = calloc<Uint16>();
    try {
      return _driverMatch(dll, drv) != 0;
    } finally {
      calloc.free(dll);
      calloc.free(drv);
    }
  }

  VjdStat deviceStatus(int deviceId) {
    final raw = _status(deviceId);
    if (raw < 0 || raw >= VjdStat.values.length) return VjdStat.unkn;
    return VjdStat.values[raw];
  }

  bool deviceExists(int deviceId) => _exists(deviceId) != 0;
  bool acquire(int deviceId) => _acquire(deviceId) != 0;
  void relinquish(int deviceId) => _relinquish(deviceId);
  bool reset(int deviceId) => _reset(deviceId) != 0;
  int buttonCount(int deviceId) => _buttonCount(deviceId);

  bool axisExists(int deviceId, int usage) =>
      _axisExists(deviceId, usage) != 0;

  /// Logical axis range, `(0x1, 0x8000)` when the query fails.
  (int, int) axisRange(int deviceId, int usage) {
    final out = calloc<Int32>();
    try {
      if (_axisMin(deviceId, usage, out) != 0 && out.value < 0x8000) {
        final min = out.value;
        if (_axisMax(deviceId, usage, out) != 0 && out.value > min) {
          return (min, out.value);
        }
      }
    } finally {
      calloc.free(out);
    }
    return (0x1, 0x8000);
  }

  /// Writes an axis value clamped to the driver's legal range.
  bool setAxis(int value, int deviceId, int usage) {
    final (min, max) = axisRange(deviceId, usage);
    if (value < min) value = min;
    if (value > max) value = max;
    return _setAxis(value, deviceId, usage) != 0;
  }

  bool setBtn(bool pressed, int deviceId, int button) =>
      _setBtn(pressed ? 1 : 0, deviceId, button) != 0;
}
