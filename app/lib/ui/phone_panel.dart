/// QR pairing panel (receiver side): big QR of the phone-link URL, LAN
/// address chips, live phone status and the server toggle.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:qr_flutter/qr_flutter.dart';

import '../core/engine.dart';
import '../core/phone_link.dart';
import '../core/qr_payload.dart';

class PhonePanel extends StatefulWidget {
  const PhonePanel({super.key, required this.engine});

  final MapperEngine engine;

  @override
  State<PhonePanel> createState() => _PhonePanelState();
}

class _PhonePanelState extends State<PhonePanel> {
  List<String> _ips = const [];

  @override
  void initState() {
    super.initState();
    _refreshIps();
  }

  Future<void> _refreshIps() async {
    final ips = await PhoneLink.lanIps();
    if (mounted) setState(() => _ips = ips);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.engine,
      builder: (context, _) {
        final engine = widget.engine;
        final port = engine.phonePort;
        final urls = [for (final ip in _ips) QrPayload.build(ip, port ?? 9870)];

        return Card(
          color: const Color(0xFF12151B),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.qr_code_2, color: cs.primary, size: 20),
                    const SizedBox(width: 8),
                    Text('Phone Controller',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    Switch(
                      value: engine.profile.phoneEnabled,
                      onChanged: (v) => engine.setPhoneEnabled(v),
                      activeColor: cs.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (!engine.phoneServerRunning) ...[
                  Text(
                    engine.phoneError ??
                        'Phone link is off — flip the switch to pair a phone.',
                    style: const TextStyle(color: Color(0xFF7A8089)),
                  ),
                  if (engine.phoneError != null)
                    TextButton.icon(
                      onPressed: _refreshIps,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry'),
                    ),
                ] else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // QR on a white tile — scanners need the contrast.
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: urls.isEmpty
                            ? const SizedBox(
                                width: 170,
                                height: 170,
                                child: Center(
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                ),
                              )
                            : QrImageView(
                                data: urls.first,
                                size: 170,
                                padding: EdgeInsets.zero,
                              ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Scan with your RingX phone app',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            const Text(
                                'Phone app → Scan QR. Browsers: open the URL '
                                'below on the phone.',
                                style: TextStyle(
                                    color: Color(0xFF7A8089), fontSize: 12)),
                            const SizedBox(height: 10),
                            if (urls.isEmpty)
                              Row(children: [
                                const Text('No LAN address found',
                                    style: TextStyle(
                                        color: Color(0xFF7A8089),
                                        fontSize: 12)),
                                TextButton.icon(
                                    onPressed: _refreshIps,
                                    icon: const Icon(Icons.refresh, size: 14),
                                    label: const Text('Refresh',
                                        style: TextStyle(fontSize: 12))),
                              ])
                            else
                              for (final u in urls)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(u,
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontFamily: 'Consolas')),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.copy, size: 15),
                                        visualDensity:
                                            VisualDensity.compact,
                                        onPressed: () => Clipboard.setData(
                                            ClipboardData(text: u)),
                                      ),
                                    ],
                                  ),
                                ),
                            const SizedBox(height: 6),
                            _PhoneStatus(engine: engine),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PhoneStatus extends StatelessWidget {
  const _PhoneStatus({required this.engine});

  final MapperEngine engine;

  @override
  Widget build(BuildContext context) {
    final connected = engine.phoneConnected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: connected ? const Color(0xFF15231A) : const Color(0xFF1B2027),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected ? const Color(0xFF46A758) : const Color(0xFF7A8089),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            connected
                ? '${engine.phoneName} connected  ·  port ${engine.phonePort}'
                : 'Awaiting phone connection  ·  port ${engine.phonePort}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
