/// Pairing screen: scan the receiver's QR, find it on WiFi, or type the
/// address. Once connected, swaps to the controller.
library;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/discovery.dart';
import '../core/qr_payload.dart';
import 'controller_screen.dart';
import 'phone_app.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  bool _scannerOn = false;
  bool _connecting = false;
  bool _searching = false;
  String? _foundPc;
  String? _lastUrl;
  final _hostCtl = TextEditingController();
  final _portCtl = TextEditingController(text: '9870');
  final _nameCtl = TextEditingController(text: 'Android phone');

  @override
  void initState() {
    super.initState();
    _nameCtl.text = phoneSession.phoneName;
    PhoneSession.lastUrl().then((u) {
      if (mounted && u != null) setState(() => _lastUrl = u);
    });
    phoneSession.addListener(_onSession);
  }

  @override
  void dispose() {
    phoneSession.removeListener(_onSession);
    _hostCtl.dispose();
    _portCtl.dispose();
    _nameCtl.dispose();
    super.dispose();
  }

  void _onSession() {
    if (phoneSession.connected && mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => const ControllerScreen(),
      ));
    }
  }

  Future<void> _connect(String url) async {
    if (_connecting || phoneSession.connected) return;
    setState(() => _connecting = true);
    final (ok, err) = await phoneSession.connect(url);
    if (!mounted) return;
    setState(() => _connecting = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err ?? 'Connection failed.'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _findPc() async {
    if (_searching) return;
    setState(() {
      _searching = true;
      _foundPc = null;
    });
    final found = await DiscoveryFinder.find();
    if (!mounted) return;
    setState(() {
      _searching = false;
      _foundPc = found;
    });
    if (found != null) {
      final hp = QrPayload.hostPort(found);
      _hostCtl.text = hp?.$1 ?? '';
      _portCtl.text = (hp?.$2 ?? 9870).toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('RingX Controller')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Header(cs: cs),
          const SizedBox(height: 16),
          _Card(
            icon: Icons.qr_code_scanner,
            title: 'Scan the PC QR code',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'On the PC: Dashboard → Phone Controller → big QR. '
                    'Point the camera at it.',
                    style: TextStyle(color: Color(0xFF7A8089), fontSize: 12)),
                const SizedBox(height: 10),
                if (_scannerOn)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 260,
                      child: MobileScanner(
                        onDetect: (capture) {
                          for (final b in capture.barcodes) {
                            final raw = b.rawValue;
                            if (raw == null) continue;
                            if (QrPayload.tryParse(raw) != null) {
                              _connect(raw);
                              break;
                            }
                          }
                        },
                      ),
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => setState(() => _scannerOn = true),
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: const Text('Start camera'),
                    ),
                  ),
                if (_scannerOn)
                  TextButton.icon(
                    onPressed: () => setState(() => _scannerOn = false),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Stop camera'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Card(
            icon: Icons.wifi_find,
            title: 'Find a PC on this WiFi',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_foundPc == null)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _searching ? null : _findPc,
                      icon: _searching
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.radar, size: 18),
                      label: Text(_searching ? 'Searching…' : 'Find PC'),
                    ),
                  )
                else
                  Row(
                    children: [
                      const Icon(Icons.computer, size: 18, color: Color(0xFF46A758)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_foundPc!,
                              style: const TextStyle(fontSize: 13))),
                      FilledButton.tonal(
                        onPressed: () => _connect(_foundPc!),
                        child: const Text('Connect'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Card(
            icon: Icons.dns_outlined,
            title: 'Type it in',
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _hostCtl,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                            labelText: 'PC address', hintText: '192.168.1.5'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _portCtl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Port'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _connecting
                        ? null
                        : () => _connect(
                            'ws://${_hostCtl.text.trim()}:${_portCtl.text.trim()}'),
                    child: _connecting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Connect'),
                  ),
                ),
              ],
            ),
          ),
          if (_lastUrl != null) ...[
            const SizedBox(height: 12),
            _Card(
              icon: Icons.history,
              title: 'Last connection',
              child: Row(
                children: [
                  Expanded(
                      child: Text(_lastUrl!,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13))),
                  FilledButton.tonal(
                    onPressed: () => _connect(_lastUrl!),
                    child: const Text('Reconnect'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _Card(
            icon: Icons.badge_outlined,
            title: 'Phone name (shows on the PC)',
            child: TextField(
              controller: _nameCtl,
              decoration: const InputDecoration(hintText: 'My phone'),
              onChanged: (v) => phoneSession.phoneName =
                  v.trim().isEmpty ? 'Android phone' : v.trim(),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              phoneSession.connecting
                  ? 'Connecting…'
                  : 'RingX Controller 0.2.0 — free, offline, no account',
              style: const TextStyle(color: Color(0xFF7A8089), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.cs});

  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: cs.primary, width: 5),
          ),
          child: Icon(Icons.sports_esports, color: cs.primary, size: 30),
        ),
        const SizedBox(height: 10),
        Text('Pair with your PC',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Scan, search, or type — then drive.',
            style: TextStyle(color: Color(0xFF7A8089))),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: const Color(0xFF12151B),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: cs.primary, size: 18),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleSmall),
            ]),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
