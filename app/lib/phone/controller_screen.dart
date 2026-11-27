/// The driving screen: landscape, renders the active template's elements,
/// aggregates wheel/pedals/sticks/tilt into one state and pushes it to the
/// PC at ~20 Hz (same cadence as the web controller).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../core/phone_proto.dart';
import '../core/templates.dart';
import 'elements.dart';
import 'editor_screen.dart';
import 'phone_app.dart';

class ControllerScreen extends StatefulWidget {
  const ControllerScreen({super.key});

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen> {
  Template? _tpl;
  int _page = 0;

  // ---- input state ---------------------------------------------------------
  double _wheelSteer = 0;
  bool _wheelTouched = false;
  double _gas = 0;
  double _brake = 0;
  Offset _stickL = Offset.zero;
  Offset _stickR = Offset.zero;
  final Set<int> _buttons = {};
  int _activeGear = -1;

  // ---- options -------------------------------------------------------------
  bool _tiltOn = false;
  bool _tiltInvert = false;
  double _tiltZero = 0;
  double _tiltSteer = 0;
  bool _autoCenter = true;
  StreamSubscription<AccelerometerEvent>? _tiltSub;

  Timer? _sendTimer;

  @override
  void initState() {
    super.initState();
    _tpl = templatePrefs.active;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    phoneSession.addListener(_onSession);
    _sendTimer = Timer.periodic(const Duration(milliseconds: 20), (_) => _send());
  }

  @override
  void dispose() {
    phoneSession.removeListener(_onSession);
    _tiltSub?.cancel();
    _sendTimer?.cancel();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _onSession() {
    if (!phoneSession.connected && mounted) {
      Navigator.of(context).pop();
    }
  }

  // ---- aggregation ---------------------------------------------------------

  void _send() {
    if (!phoneSession.connected) return;
    if (_autoCenter && !_wheelTouched) {
      _wheelSteer *= 0.86;
      if (_wheelSteer.abs() < 0.01) _wheelSteer = 0;
    }
    final steer =
        (_wheelSteer + _tiltSteer + _stickL.dx + _stickR.dx).clamp(-1.0, 1.0);
    final thr = _max3(_gas, _up(_stickL), _up(_stickR)).clamp(0.0, 1.0);
    final brk = _max3(_brake, _down(_stickL), _down(_stickR))
        .clamp(0.0, 1.0);
    phoneSession.sendState(steer, thr, brk, _buttons);

    // Repaint only when something visible moved (throttled to ~10 Hz).
    final now = DateTime.now().millisecondsSinceEpoch;
    if (mounted &&
        (steer != _lastPaintedSteer ||
            thr != _lastPaintedThr ||
            brk != _lastPaintedBrk ||
            _buttons.length != _lastPaintedBtns) &&
        now - _lastPaintMs > 90) {
      _lastPaintedSteer = steer;
      _lastPaintedThr = thr;
      _lastPaintedBrk = brk;
      _lastPaintedBtns = _buttons.length;
      _lastPaintMs = now;
      setState(() {});
    }
  }

  double _lastPaintedSteer = 0;
  double _lastPaintedThr = 0;
  double _lastPaintedBrk = 0;
  int _lastPaintedBtns = 0;
  int _lastPaintMs = 0;

  static double _up(Offset s) => s.dy < 0 ? -s.dy : 0;
  static double _down(Offset s) => s.dy > 0 ? s.dy : 0;
  static double _max3(double a, double b, double c) {
    var m = a;
    if (b > m) m = b;
    if (c > m) m = c;
    return m;
  }

  void _setButton(int btn, bool down) {
    down ? _buttons.add(btn) : _buttons.remove(btn);
  }

  // ---- tilt ----------------------------------------------------------------

  double _tiltRawX = 0;

  void _toggleTilt(bool on) {
    _tiltSub?.cancel();
    _tiltSub = null;
    _tiltSteer = 0;
    if (on) {
      _tiltZero = 0; // recalibrate on enable
      _tiltSub = accelerometerEvents.listen((e) {
        _tiltRawX = e.x;
        var v = (e.x - _tiltZero) / 9.81 * 1.6; // ~35° for full lock
        if (_tiltInvert) v = -v;
        _tiltSteer = v.clamp(-1.0, 1.0);
      });
    }
    setState(() => _tiltOn = on);
  }

  // ---- UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tpl = _tpl;
    final pages = tpl?.pages ?? const <TplPage>[];
    if (_page >= pages.length) _page = 0;
    final page = pages.isEmpty ? null : pages[_page];

    return Scaffold(
      backgroundColor: const Color(0xFF0E1116),
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              session: phoneSession,
              cs: cs,
              templateName: tpl?.name ?? 'No template',
              pages: pages.length,
              page: _page,
              onPage: (i) => setState(() => _page = i),
              onMenu: _openMenu,
            ),
            Expanded(
              child: page == null
                  ? const Center(
                      child: Text('No template selected.',
                          style: TextStyle(color: Color(0xFF7A8089))))
                  : LayoutBuilder(
                      builder: (context, cons) {
                        final w = cons.maxWidth;
                        final h = cons.maxHeight;
                        final minSide = w < h ? w : h;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (final e in page.elements)
                              () {
                                final side = e.size * minSide;
                                var bw = side;
                                var bh = side;
                                var dx = -side / 2;
                                var dy = -side / 2;
                                switch (e.kind) {
                                  case ElKind.prnd:
                                    bw = side * 2.6;
                                    dx = -bw / 2;
                                    bh = side * 0.85;
                                    dy = -bh / 2;
                                  case ElKind.shift:
                                    bw = side * 1.7;
                                    dx = -bw / 2;
                                    bh = side * 1.5;
                                    dy = -bh / 2;
                                  case ElKind.pedalGas ||
                                      ElKind.pedalBrake:
                                    bh = side * 1.15;
                                    dy = -bh / 2;
                                    bw = side * 0.75;
                                    dx = -bw / 2;
                                  default:
                                    break;
                                }
                                return Positioned(
                                  left: e.x * w + dx,
                                  top: e.y * h + dy,
                                  width: bw,
                                  height: bh,
                                  child: _elementWidget(e),
                                );
                              }(),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _elementWidget(TplElement e) {
    switch (e.kind) {
      case ElKind.wheel:
        return WheelWidget(
          value: _wheelSteer,
          onSteer: (v) {
            _wheelTouched = true;
            _wheelSteer = v;
          },
        );
      case ElKind.pedalGas:
        return PedalWidget(
          value: _gas,
          onPedal: (v) => _gas = v,
          label: 'GAS',
          color: green,
        );
      case ElKind.pedalBrake:
        return PedalWidget(
          value: _brake,
          onPedal: (v) => _brake = v,
          label: 'BRAKE',
          color: red,
        );
      case ElKind.stick:
        final isLeft = e.stickMap == 'left';
        return StickWidget(
          offset: isLeft ? _stickL : _stickR,
          onStick: (o) {
            if (isLeft) {
              _stickL = o;
            } else {
              _stickR = o;
            }
          },
        );
      case ElKind.prnd:
        return PrndWidget(
          baseButton: e.button,
          onButton: (b) {
            _setButton(b.$1, b.$2);
            if (b.$2) _activeGear = b.$1 - e.button;
          },
          activeGear: _activeGear,
        );
      case ElKind.shift:
        return ShiftWidget(
          baseButton: e.button,
          onButton: (b) => _setButton(b.$1, b.$2),
        );
      case ElKind.button:
        final color = switch (e.label) {
          'HORN' => amber,
          'E-BRK' => red,
          'SIG L' || 'SIG R' => green,
          _ => amber,
        };
        return TouchButtonWidget(
          pressed: _buttons.contains(e.button),
          label: e.label,
          color: color,
          onPressed: (down) => _setButton(e.button, down),
        );
    }
  }

  Future<void> _openMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF12151B),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(12)),
            _menuTile(Icons.tune, 'Tilt steering',
                trailing: Switch(value: _tiltOn, onChanged: _toggleTilt),
                onTap: () {}),
            _menuTile(Icons.straighten, 'Re-center tilt',
                onTap: () => _tiltZero = _tiltRawX),
            _menuTile(Icons.swap_horiz, 'Invert tilt',
                trailing: Switch(
                    value: _tiltInvert,
                    onChanged: (v) => _tiltInvert = v),
                onTap: () {}),
            _menuTile(Icons.restart_alt, 'Auto-center wheel',
                trailing: Switch(
                    value: _autoCenter,
                    onChanged: (v) => _autoCenter = v),
                onTap: () {}),
            const Divider(color: Color(0xFF23262E)),
            _menuTile(Icons.edit_outlined, 'Edit layout', onTap: () {
              Navigator.of(sheet).pop('edit');
            }),
            _menuTile(Icons.dashboard_outlined, 'Switch template',
                onTap: () {
                  Navigator.of(sheet).pop('templates');
                }),
            _menuTile(Icons.send_outlined, 'Send template to PC', onTap: () {
              Navigator.of(sheet).pop('send');
            }),
            const Divider(color: Color(0xFF23262E)),
            _menuTile(Icons.link_off, 'Disconnect', onTap: () {
              Navigator.of(sheet).pop('disconnect');
            }),
            const Padding(padding: EdgeInsets.all(12)),
          ],
        ),
      ),
    );
    switch (action) {
      case 'edit':
        await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const EditorScreen()));
        if (mounted) {
          setState(() => _tpl = templatePrefs.active);
        }
      case 'templates':
        await _pickTemplate();
      case 'send':
        _sendTemplateToPc();
      case 'disconnect':
        phoneSession.disconnect();
    }
  }

  Widget _menuTile(IconData icon, String label,
      {Widget? trailing, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFFF5A524), size: 20),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      trailing: trailing,
      onTap: onTap == null ? null : () {},
      dense: true,
    );
  }

  Future<void> _pickTemplate() async {
    final list = templatePrefs.templates;
    final name = await showDialog<String>(
      context: context,
      builder: (d) => SimpleDialog(
        title: const Text('Switch template'),
        children: [
          for (final t in list)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(d, t.name),
              child: Text(t.name),
            ),
        ],
      ),
    );
    if (name != null) {
      await templatePrefs.setActive(name);
      setState(() {
        _tpl = templatePrefs.active;
        _page = 0;
      });
    }
  }

  void _sendTemplateToPc() {
    final t = _tpl;
    if (t == null) return;
    phoneSession.send(TemplateMsg(t.toJson()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Template sent to the PC (Templates screen).'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ));
    }
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.session,
    required this.cs,
    required this.templateName,
    required this.pages,
    required this.page,
    required this.onPage,
    required this.onMenu,
  });

  final PhoneSession session;
  final ColorScheme cs;
  final String templateName;
  final int pages;
  final int page;
  final ValueChanged<int> onPage;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            // Engine toggle — RojX-style circular START/STOP.
            GestureDetector(
              onTap: session.toggleMapping,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: session.mappingEnabled
                      ? green.withValues(alpha: 0.25)
                      : const Color(0xFF1A1D23),
                  border: Border.all(
                      color: session.mappingEnabled ? green : cs.primary,
                      width: 3),
                ),
                child: Icon(
                  session.mappingEnabled ? Icons.stop : Icons.play_arrow,
                  color: session.mappingEnabled ? green : cs.primary,
                  size: 26,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: green),
                  ),
                  const SizedBox(width: 5),
                  const Text('PC linked',
                      style: TextStyle(fontSize: 11, color: Colors.white70)),
                ]),
                Text(
                  session.mappingEnabled ? 'MAPPING ON' : 'mapping off',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: session.mappingEnabled ? green : Color(0xFF7A8089)),
                ),
              ],
            ),
            const SizedBox(width: 12),
            // Page dots.
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(templateName,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF7A8089))),
                  if (pages > 1) ...[
                    const SizedBox(width: 10),
                    for (var i = 0; i < pages; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: InkWell(
                          onTap: () => onPage(i),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i == page
                                  ? cs.primary.withValues(alpha: 0.3)
                                  : const Color(0xFF1A1D23),
                              border: Border.all(
                                  color: i == page ? cs.primary : const Color(0xFF2A2E36)),
                            ),
                            alignment: Alignment.center,
                            child: Text('${i + 1}',
                                style: const TextStyle(fontSize: 10)),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert, size: 22),
              onPressed: onMenu,
            ),
          ],
        ),
      ),
    );
  }
}
