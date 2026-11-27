/// Control templates: what the phone controller screen shows.
///
/// A template is pages of elements; each element is a positioned control
/// (wheel, pedals, buttons, stick, gear selector) with its bindings. The
/// same model is used by the phone editor, the phone controller renderer
/// and the PC "Templates" screen — it syncs over the wire as JSON.
///
/// Everything decoded from JSON (disk or network) is clamped and validated:
/// hand-edited or hostile payloads can only produce sane templates.
library;

/// Control kinds the phone can render.
enum ElKind {
  wheel('Steering Wheel'),
  pedalGas('Throttle Pedal'),
  pedalBrake('Brake Pedal'),
  button('Button'),
  stick('Thumbstick'),
  prnd('Gear Selector (PRND)'),
  shift('Paddle Shifters');

  const ElKind(this.label);
  final String label;

  /// Element is positioned freely on the page (all of them are).
  bool get draggable => true;
}

/// One control on a page. `x`/`y`/`size` are fractions of the play area so
/// the same template works on any phone size.
class TplElement {
  const TplElement({
    required this.kind,
    required this.x,
    required this.y,
    required this.size,
    this.label = '',
    this.button = 1,
    this.stickMap = 'left',
  });

  final ElKind kind;

  /// Center position, 0..1 of the play area.
  final double x;
  final double y;

  /// Element size, 0.12..0.6 of the play area's short edge.
  final double size;

  /// Short label shown on the control ('HORN', 'A', 'P'...). Max 12 chars.
  final String label;

  /// First vJoy button number (1..128). PRND uses `button..button+3`
  /// (P/R/N/D); paddles use `button`/`button+1` (+/-).
  final int button;

  /// Which stick this is when [kind] is [ElKind.stick]: 'left' or 'right'.
  final String stickMap;

  TplElement copyWith({
    double? x,
    double? y,
    double? size,
    String? label,
    int? button,
    String? stickMap,
  }) =>
      TplElement(
        kind: kind,
        x: x ?? this.x,
        y: y ?? this.y,
        size: size ?? this.size,
        label: label ?? this.label,
        button: button ?? this.button,
        stickMap: stickMap ?? this.stickMap,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'x': x,
        'y': y,
        'size': size,
        'label': label,
        'button': button,
        'stick': stickMap,
      };

  static TplElement fromJson(Map<String, dynamic> json) {
    final kind = ElKind.values
        .firstWhere((k) => k.name == json['kind'], orElse: () => ElKind.button);
    var label = (json['label'] ?? '') as String;
    if (label.length > 12) label = label.substring(0, 12);
    final stick = json['stick'] == 'right' ? 'right' : 'left';
    final button = _clampInt(json['button'], 1, 125, 1);
    return TplElement(
      kind: kind,
      x: _clampFrac(json['x'], 0.02, 0.98, 0.5),
      y: _clampFrac(json['y'], 0.02, 0.98, 0.5),
      size: _clampFrac(json['size'], 0.12, 0.6, 0.28),
      label: label,
      button: button,
      stickMap: kind == ElKind.stick ? stick : 'left',
    );
  }
}

class TplPage {
  const TplPage({required this.name, required this.elements});

  final String name;
  final List<TplElement> elements;

  /// Max elements per page — keeps junk payloads bounded.
  static const int maxElements = 24;

  TplPage copyWith({String? name, List<TplElement>? elements}) =>
      TplPage(name: name ?? this.name, elements: elements ?? this.elements);

  Map<String, dynamic> toJson() => {
        'name': name,
        'elements': elements.map((e) => e.toJson()).toList(),
      };

  static TplPage fromJson(Map<String, dynamic> json) {
    var name = json['name'] is String ? json['name'] as String : 'Page';
    if (name.isEmpty) name = 'Page';
    if (name.length > 24) name = name.substring(0, 24);
    final raw = json['elements'];
    final elements = <TplElement>[
      if (raw is List)
        for (final e in raw)
          if (e is Map) TplElement.fromJson(Map<String, dynamic>.from(e)),
    ];
    if (elements.length > maxElements) elements.length = maxElements;
    return TplPage(name: name, elements: elements);
  }
}

class Template {
  const Template({required this.name, required this.pages});

  final String name;
  final List<TplPage> pages;

  static const int maxPages = 8;

  Map<String, dynamic> toJson() => {
        'name': name,
        'pages': pages.map((p) => p.toJson()).toList(),
      };

  /// Null when the payload is not a usable template (no pages at all).
  static Template? tryParse(Map<String, dynamic> json) {
    final raw = json['pages'];
    if (raw is! List || raw.isEmpty) return null;
    return fromJson(json);
  }

  static Template fromJson(Map<String, dynamic> json) {
    var name = json['name'] is String ? json['name'] as String : 'Template';
    if (name.isEmpty) name = 'Template';
    if (name.length > 40) name = name.substring(0, 40);
    final raw = json['pages'];
    var pages = <TplPage>[
      if (raw is List)
        for (final p in raw)
          if (p is Map) TplPage.fromJson(Map<String, dynamic>.from(p)),
    ];
    if (pages.length > maxPages) pages.length = maxPages;
    if (pages.isEmpty) pages = [const TplPage(name: 'Page 1', elements: [])];
    return Template(name: name, pages: pages);
  }

  Template copyWith({String? name, List<TplPage>? pages}) =>
      Template(name: name ?? this.name, pages: pages ?? this.pages);

  // ---- Built-in layouts (RojX-style) --------------------------------------

  /// Full racing layout: wheel + tilt-ready, pedals, PRND, paddles, buttons.
  static Template racing() => Template(
        name: 'Racing',
        pages: [
          const TplPage(
            name: 'Drive',
            elements: [
              TplElement(kind: ElKind.wheel, x: 0.30, y: 0.55, size: 0.52),
              TplElement(
                  kind: ElKind.pedalGas, x: 0.86, y: 0.38, size: 0.26),
              TplElement(
                  kind: ElKind.pedalBrake, x: 0.86, y: 0.78, size: 0.26),
              TplElement(kind: ElKind.prnd, x: 0.30, y: 0.14, size: 0.42, button: 9),
              TplElement(kind: ElKind.shift, x: 0.58, y: 0.50, size: 0.30, button: 13),
              TplElement(
                  kind: ElKind.button,
                  x: 0.60, y: 0.24, size: 0.18,
                  label: 'HORN', button: 1),
              TplElement(
                  kind: ElKind.button,
                  x: 0.60, y: 0.76, size: 0.18,
                  label: 'E-BRK', button: 2),
            ],
          ),
          const TplPage(
            name: 'Extras',
            elements: [
              TplElement(kind: ElKind.wheel, x: 0.30, y: 0.55, size: 0.52),
              TplElement(
                  kind: ElKind.pedalGas, x: 0.86, y: 0.38, size: 0.26),
              TplElement(
                  kind: ElKind.pedalBrake, x: 0.86, y: 0.78, size: 0.26),
              TplElement(
                  kind: ElKind.button,
                  x: 0.58, y: 0.20, size: 0.16,
                  label: 'SIG L', button: 3),
              TplElement(
                  kind: ElKind.button,
                  x: 0.58, y: 0.44, size: 0.16,
                  label: 'SIG R', button: 4),
              TplElement(
                  kind: ElKind.button,
                  x: 0.58, y: 0.68, size: 0.16,
                  label: 'LIGHT', button: 5),
              TplElement(
                  kind: ElKind.button,
                  x: 0.58, y: 0.90, size: 0.16,
                  label: 'CAM', button: 6),
            ],
          ),
        ],
      );

  /// Dual-thumbstick layout for non-racing games.
  static Template gamepad() => Template(
        name: 'Gamepad',
        pages: [
          const TplPage(
            name: 'Pad',
            elements: [
              TplElement(kind: ElKind.stick, x: 0.20, y: 0.62, size: 0.34,
                  stickMap: 'left'),
              TplElement(kind: ElKind.stick, x: 0.80, y: 0.62, size: 0.34,
                  stickMap: 'right'),
              TplElement(
                  kind: ElKind.button, x: 0.63, y: 0.24, size: 0.16,
                  label: 'Y', button: 1),
              TplElement(
                  kind: ElKind.button, x: 0.55, y: 0.40, size: 0.16,
                  label: 'X', button: 2),
              TplElement(
                  kind: ElKind.button, x: 0.71, y: 0.40, size: 0.16,
                  label: 'B', button: 3),
              TplElement(
                  kind: ElKind.button, x: 0.63, y: 0.56, size: 0.16,
                  label: 'A', button: 4),
              TplElement(
                  kind: ElKind.button, x: 0.37, y: 0.22, size: 0.14,
                  label: 'LB', button: 5),
              TplElement(
                  kind: ElKind.button, x: 0.87, y: 0.22, size: 0.14,
                  label: 'RB', button: 6),
              TplElement(
                  kind: ElKind.button, x: 0.37, y: 0.90, size: 0.14,
                  label: 'MENU', button: 7),
            ],
          ),
        ],
      );

  /// Minimal layout: wheel + two pedals only.
  static Template lite() => Template(
        name: 'Lite',
        pages: [
          const TplPage(
            name: 'Drive',
            elements: [
              TplElement(kind: ElKind.wheel, x: 0.34, y: 0.55, size: 0.56),
              TplElement(
                  kind: ElKind.pedalGas, x: 0.86, y: 0.38, size: 0.26),
              TplElement(
                  kind: ElKind.pedalBrake, x: 0.86, y: 0.78, size: 0.26),
            ],
          ),
        ],
      );

  /// All factory layouts, in menu order.
  static List<Template> presets() =>
      [racing(), gamepad(), lite()];
}

int _clampInt(dynamic v, int min, int max, int fallback) {
  final i = v is num ? v.toInt() : fallback;
  return i < min ? min : (i > max ? max : i);
}

double _clampFrac(dynamic v, double min, double max, double fallback) {
  final d = v is num ? v.toDouble() : fallback;
  if (d.isNaN) return fallback;
  return d < min ? min : (d > max ? max : d);
}
