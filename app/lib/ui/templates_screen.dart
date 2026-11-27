/// Templates screen (receiver): factory layouts plus the templates the
/// phone pushed over the link, with a live page preview. Editing happens on
/// the phone; this screen is the PC-side view of what will be played.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/engine.dart';
import '../core/templates.dart';

class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key, this.engine});

  /// May be null (phone-only builds still show the factory layouts).
  final MapperEngine? engine;

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  final List<Template> _received = [];
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  void initState() {
    super.initState();
    final engine = widget.engine;
    if (engine != null) {
      _sub = engine.templatesFromPhone.listen((raw) {
        final t = Template.tryParse(raw);
        if (t == null) return;
        setState(() {
          // Same-name template from the same phone replaces its old copy.
          _received.removeWhere((x) => x.name == t.name);
          _received.insert(0, t);
        });
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Control Templates',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text(
          'Layouts live on the phone. Build and edit them there (Templates '
          'tab), then "Send to PC" — they show up here instantly.',
          style: TextStyle(color: Color(0xFF7A8089), fontSize: 12),
        ),
        const SizedBox(height: 16),
        if (_received.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.phonelink_ring, color: cs.primary, size: 18),
              const SizedBox(width: 6),
              Text('From your phone',
                  style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          for (final t in _received)
            _TemplateCard(
              template: t,
              accent: cs.primary,
              onRemove: () => setState(() => _received.remove(t)),
            ),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Icon(Icons.factory_outlined, color: cs.primary, size: 18),
            const SizedBox(width: 6),
            Text('Factory layouts',
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 8),
        for (final t in Template.presets())
          _TemplateCard(template: t, accent: cs.primary),
      ],
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.accent,
    this.onRemove,
  });

  final Template template;
  final Color accent;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final pages = template.pages;
    return Card(
      color: const Color(0xFF16181D),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Landscape mini-preview of page 1.
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 220,
                height: 110,
                child: CustomPaint(
                  painter: _PagePreviewPainter(page: pages.first, accent: accent),
                  size: const Size(220, 110),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(template.name,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '${pages.length} page${pages.length == 1 ? '' : 's'} · '
                    '${pages.fold<int>(0, (n, p) => n + p.elements.length)} '
                    'elements',
                    style: const TextStyle(
                        color: Color(0xFF7A8089), fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (var i = 0; i < pages.length; i++)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1D23),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF2A2E36)),
                          ),
                          child: Text(
                            '${i + 1}. ${pages[i].name}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                  if (onRemove != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        tooltip: 'Forget this template',
                        onPressed: onRemove,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws one page as colored element tags — RojX-style: amber for axes,
/// blue for sticks, dark pills for buttons.
class _PagePreviewPainter extends CustomPainter {
  _PagePreviewPainter({required this.page, required this.accent});

  final TplPage page;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF0E1116));
    // faint grid
    final grid = Paint()
      ..color = const Color(0x1423262E)
      ..strokeWidth = 1;
    for (var x = size.width / 6; x < size.width; x += size.width / 6) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = size.height / 4; y < size.height; y += size.height / 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (final e in page.elements) {
      final w = e.size * size.height * 1.6;
      final h = e.size * size.height;
      final rect = Rect.fromCenter(
          center: Offset(e.x * size.width, e.y * size.height),
          width: w.clamp(10, size.width),
          height: h.clamp(8, size.height));
      final fill = Paint()
        ..color = switch (e.kind) {
          ElKind.wheel ||
          ElKind.pedalGas ||
          ElKind.pedalBrake =>
            accent.withValues(alpha: 0.22),
          ElKind.stick => const Color(0x3358A6FF),
          ElKind.prnd || ElKind.shift => const Color(0x3346A758),
          ElKind.button => const Color(0x331A1D23),
        };
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = switch (e.kind) {
          ElKind.wheel ||
          ElKind.pedalGas ||
          ElKind.pedalBrake => accent,
          ElKind.stick => const Color(0xFF58A6FF),
          ElKind.prnd || ElKind.shift => const Color(0xFF46A758),
          ElKind.button => const Color(0xFF3A404D),
        };
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
      canvas.drawRRect(rrect, fill);
      canvas.drawRRect(rrect, stroke);
      if (e.label.isNotEmpty && rect.width > 22) {
        _tinyText(canvas, e.label, rect);
      }
    }
  }

  void _tinyText(Canvas canvas, String label, Rect rect) {
    final tp = TextPainter(
      text: TextSpan(
          text: label,
          style: const TextStyle(
              color: Color(0xFFD7DAE0), fontSize: 7.5)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: rect.width);
    tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_PagePreviewPainter old) =>
      old.page != page || old.accent != accent;
}
