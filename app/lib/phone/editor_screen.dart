/// Template editor: drag elements around the page, add new ones from the
/// palette, tune size/label/button per element, manage pages and templates.
/// Everything persists to the phone's template store immediately.
library;

import 'package:flutter/material.dart';

import '../core/phone_proto.dart';
import '../core/templates.dart';
import 'elements.dart';
import 'phone_app.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  List<Template> _list = [];
  late int _tplIdx;
  int _page = 0;
  int? _selIndex;

  Template get _tpl => _list[_tplIdx];
  TplPage get _pageObj => _tpl.pages[_page];

  @override
  void initState() {
    super.initState();
    _list = templatePrefs.templates;
    if (_list.isEmpty) _list = [Template.lite()];
    final active = templatePrefs.active;
    _tplIdx = _list.indexOf(active ?? _list.first);
    if (_tplIdx < 0) _tplIdx = 0;
  }

  // ---- persistence ---------------------------------------------------------

  Future<void> _commit({List<Template>? list}) async {
    final next = list ?? _list;
    _list = next;
    await templatePrefs.saveAll(next);
    if (mounted) setState(() {});
  }

  void _mutatePage(TplPage page) {
    final pages = [..._tpl.pages];
    pages[_page] = page;
    _commit(list: [
      for (var i = 0; i < _list.length; i++)
        i == _tplIdx ? _tpl.copyWith(pages: pages) : _list[i],
    ]);
  }

  // ---- template ops --------------------------------------------------------

  Future<void> _templateMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF12151B),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline,
                  color: Color(0xFFF5A524)),
              title: const Text('Rename template'),
              onTap: () => Navigator.pop(sheet, 'rename'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.copy_all, color: Color(0xFFF5A524)),
              title: const Text('Duplicate'),
              onTap: () => Navigator.pop(sheet, 'dup'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFFE5484D)),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(sheet, 'del'),
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt, color: Color(0xFFF5A524)),
              title: const Text('Reset to factory layout'),
              onTap: () => Navigator.pop(sheet, 'reset'),
            ),
            ListTile(
              leading: const Icon(Icons.send_outlined, color: Color(0xFFF5A524)),
              title: const Text('Send to PC'),
              onTap: () => Navigator.pop(sheet, 'send'),
            ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'rename':
        final name = await _askText('Template name', _tpl.name);
        if (name != null && name.trim().isNotEmpty) {
          await templatePrefs.setActive(_tpl.name); // keep active
          _commit(list: [
            for (var i = 0; i < _list.length; i++)
              i == _tplIdx ? _tpl.copyWith(name: name.trim()) : _list[i],
          ]);
        }
      case 'dup':
        final copy = _tpl.copyWith(name: '${_tpl.name} copy');
        final next = [..._list];
        next.insert(_tplIdx + 1, copy);
        _tplIdx++;
        _commit(list: next);
      case 'del':
        if (_list.length <= 1) {
          _toast('Keep at least one template.');
          return;
        }
        final next = [..._list]..removeAt(_tplIdx);
        _tplIdx = _tplIdx >= next.length ? next.length - 1 : _tplIdx;
        _commit(list: next);
      case 'reset':
        final factory = Template.presets()
            .firstWhere((t) => t.name == _tpl.name, orElse: Template.racing);
        _commit(list: [
          for (var i = 0; i < _list.length; i++) i == _tplIdx ? factory : _list[i],
        ]);
      case 'send':
        phoneSession.send(TemplateMsg(_tpl.toJson()));
        _toast('Sent to the PC (Templates screen).');
    }
  }

  Future<String?> _askText(String title, String initial) {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: const Color(0xFF16181D),
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: TextField(controller: ctl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(d, ctl.text),
              child: const Text('OK')),
        ],
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  // ---- element ops ---------------------------------------------------------

  void _addElement(ElKind kind) {
    final count = _pageObj.elements.length;
    if (count >= TplPage.maxElements) {
      _toast('Too many elements on this page.');
      return;
    }
    final e = TplElement(
      kind: kind,
      x: 0.5,
      y: 0.5,
      size: switch (kind) {
        ElKind.wheel => 0.5,
        ElKind.pedalGas || ElKind.pedalBrake => 0.24,
        ElKind.prnd => 0.38,
        ElKind.shift => 0.28,
        _ => 0.16,
      },
      label: switch (kind) {
        ElKind.button => 'BTN',
        _ => '',
      },
      button: _nextFreeButton(),
      stickMap: kind == ElKind.stick
          ? (_pageObj.elements.where((e) => e.kind == ElKind.stick).length ==
                  0
              ? 'left'
              : 'right')
          : 'left',
    );
    _mutatePage(_pageObj.copyWith(elements: [..._pageObj.elements, e]));
    setState(() => _selIndex = count);
  }

  int _nextFreeButton() {
    final used = <int>{
      for (final p in _tpl.pages)
        for (final e in p.elements)
          if (e.kind == ElKind.prnd)
            ...List.generate(4, (i) => e.button + i)
          else if (e.kind == ElKind.shift)
            ...List.generate(2, (i) => e.button + i)
          else
            e.button,
    };
    for (var b = 1; b <= 128; b++) {
      if (!used.contains(b)) return b;
    }
    return 1;
  }

  void _updateElement(int i, TplElement e) {
    final els = [..._pageObj.elements];
    els[i] = e;
    _mutatePage(_pageObj.copyWith(elements: els));
  }

  void _deleteElement(int i) {
    final els = [..._pageObj.elements]..removeAt(i);
    _mutatePage(_pageObj.copyWith(elements: els));
    setState(() => _selIndex = null);
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: DropdownButton<int>(
          value: _tplIdx,
          underline: const SizedBox.shrink(),
          items: [
            for (var i = 0; i < _list.length; i++)
              DropdownMenuItem(
                  value: i, child: Text(_list[i].name)),
          ],
          onChanged: (i) => setState(() {
            _tplIdx = i!;
            _page = 0;
            _selIndex = null;
            templatePrefs.setActive(_tpl.name);
          }),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.more_vert), onPressed: _templateMenu),
        ],
      ),
      body: Column(
        children: [
          // Play-area canvas.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: AspectRatio(
              aspectRatio: 1.9,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0E1116),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF23262E)),
                ),
                child: LayoutBuilder(
                  builder: (context, cons) {
                    final w = cons.maxWidth;
                    final h = cons.maxHeight;
                    final minSide = w < h ? w : h;
                    final els = _pageObj.elements;
                    return Stack(
                      children: [
                        for (var i = 0; i < els.length; i++)
                          () {
                            final e = els[i];
                            final side = e.size * minSide;
                            var bw = side, bh = side;
                            switch (e.kind) {
                              case ElKind.prnd:
                                bw = side * 2.6;
                                bh = side * 0.85;
                              case ElKind.shift:
                                bw = side * 1.7;
                                bh = side * 1.5;
                              case ElKind.pedalGas || ElKind.pedalBrake:
                                bh = side * 1.15;
                                bw = side * 0.75;
                              default:
                                break;
                            }
                            return Positioned(
                              left: (e.x * w - bw / 2).clamp(0.0, w - bw),
                              top: (e.y * h - bh / 2).clamp(0.0, h - bh),
                              width: bw,
                              height: bh,
                              child: GestureDetector(
                                onPanUpdate: (d) => _updateElement(
                                    i,
                                    e.copyWith(
                                      x: ((e.x + d.delta.dx / w))
                                          .clamp(0.02, 0.98),
                                      y: ((e.y + d.delta.dy / h))
                                          .clamp(0.02, 0.98),
                                    )),
                                onTap: () =>
                                    setState(() => _selIndex = i),
                                child: ElementPreview(
                                    element: e, selected: _selIndex == i),
                              ),
                            );
                          }(),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          // Page chips.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < _tpl.pages.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(_tpl.pages[i].name),
                        selected: i == _page,
                        onSelected: (_) =>
                            setState(() { _page = i; _selIndex = null; }),
                        selectedColor: cs.primary.withValues(alpha: 0.25),
                      ),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16, color: Color(0xFFF5A524)),
                    label: const Text('Page'),
                    onPressed: () async {
                      if (_tpl.pages.length >= Template.maxPages) {
                        _toast('Page limit reached.');
                        return;
                      }
                      final name = await _askText('Page name', 'Page ${_tpl.pages.length + 1}');
                      if (name == null || name.trim().isEmpty) return;
                      _page = _tpl.pages.length;
                      _selIndex = null;
                      _commit(list: [
                        for (var i = 0; i < _list.length; i++)
                          i == _tplIdx
                              ? _tpl.copyWith(pages: [
                                  ..._tpl.pages,
                                  TplPage(
                                      name: name.trim().isNotEmpty
                                          ? name.trim()
                                          : 'Page ${_tpl.pages.length + 1}',
                                      elements: const []),
                                ])
                              : _list[i],
                      ]);
                    },
                  ),
                ],
              ),
            ),
          ),
          // Selected element properties.
          if (_selIndex != null && _selIndex! < _pageObj.elements.length)
            _PropsSheet(
              element: _pageObj.elements[_selIndex!],
              onChange: (e) => _updateElement(_selIndex!, e),
              onDelete: () => _deleteElement(_selIndex!),
            ),
          // Palette.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final k in ElKind.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        avatar: Icon(
                          switch (k) {
                            ElKind.wheel => Icons.radio_button_checked,
                            ElKind.pedalGas => Icons.keyboard_double_arrow_up,
                            ElKind.pedalBrake => Icons.keyboard_double_arrow_down,
                            ElKind.button => Icons.circle_outlined,
                            ElKind.stick => Icons.gamepad_outlined,
                            ElKind.prnd => Icons.view_module_outlined,
                            ElKind.shift => Icons.unfold_more,
                          },
                          size: 16,
                          color: const Color(0xFFF5A524),
                        ),
                        label: Text(switch (k) {
                          ElKind.pedalGas => 'Gas',
                          ElKind.pedalBrake => 'Brake',
                          ElKind.shift => 'Paddles',
                          _ => k.label.split(' ').first,
                        }),
                        onPressed: () => _addElement(k),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PropsSheet extends StatelessWidget {
  const _PropsSheet({
    required this.element,
    required this.onChange,
    required this.onDelete,
  });

  final TplElement element;
  final ValueChanged<TplElement> onChange;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF12151B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text('${element.kind.label} · ${element.button}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: onDelete,
              ),
            ],
          ),
          Row(
            children: [
              const SizedBox(
                  width: 64, child: Text('Size', style: TextStyle(fontSize: 12))),
              Expanded(
                child: Slider(
                  min: 0.12,
                  max: 0.6,
                  value: element.size,
                  activeColor: cs.primary,
                  onChanged: (v) => onChange(element.copyWith(size: v)),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text('${(element.size * 100).round()}%',
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 11)),
              ),
            ],
          ),
          Row(
            children: [
              const SizedBox(
                  width: 64, child: Text('Label', style: TextStyle(fontSize: 12))),
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: element.label)
                    ..selection = TextSelection.collapsed(
                        offset: element.label.length),
                  decoration: const InputDecoration(
                      isDense: true, hintText: 'HORN, A, SIG L…'),
                  maxLength: 12,
                  onChanged: (v) => onChange(element.copyWith(label: v)),
                ),
              ),
            ],
          ),
          if (element.kind == ElKind.stick)
            Row(
              children: [
                const Text('Stick side', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('Left'),
                  selected: element.stickMap == 'left',
                  onSelected: (_) =>
                      onChange(element.copyWith(stickMap: 'left')),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Right'),
                  selected: element.stickMap == 'right',
                  onSelected: (_) =>
                      onChange(element.copyWith(stickMap: 'right')),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
