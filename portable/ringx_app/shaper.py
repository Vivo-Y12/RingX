"""Analog shaping for keyboard-driven axes.

Turns on/off key state into a ramped, curved, deadzone-safe output value.
Pure logic, no Windows dependencies — unit tested in tests/.
"""

CURVES = ("linear", "smooth", "aggressive")


def _clamp_int(v, lo, hi, fallback):
    try:
        i = int(v)
    except (TypeError, ValueError):
        return fallback
    return lo if i < lo else hi if i > hi else i


def _clamp_float(v, lo, hi, fallback):
    try:
        f = float(v)
    except (TypeError, ValueError):
        return fallback
    return lo if f < lo else hi if f > hi else f


class AxisConfig:
    """Tuning for one analog axis (all values validated on load)."""

    __slots__ = ("attack_ms", "decay_ms", "curve", "anti_dz")

    def __init__(self, attack_ms=350, decay_ms=180, curve="smooth",
                 anti_dz=0.05):
        self.attack_ms = _clamp_int(attack_ms, 10, 5000, 350)
        self.decay_ms = _clamp_int(decay_ms, 10, 5000, 180)
        self.curve = curve if curve in CURVES else "smooth"
        self.anti_dz = _clamp_float(anti_dz, 0.0, 0.25, 0.05)

    def __eq__(self, other):
        return isinstance(other, AxisConfig) and self.to_dict() == \
            other.to_dict()

    def to_dict(self):
        return {"attack_ms": self.attack_ms, "decay_ms": self.decay_ms,
                "curve": self.curve, "anti_dz": self.anti_dz}

    @classmethod
    def from_dict(cls, d):
        d = d if isinstance(d, dict) else {}
        return cls(d.get("attack_ms"), d.get("decay_ms"),
                   d.get("curve"), d.get("anti_dz"))


class AxisShaper:
    """Integrates one axis toward a signed target (-1.0 .. 1.0).

    Steering: -1 full left .. +1 full right. Pedals: 0 released .. 1 full.
    Pressing (target non-zero) ramps at attack rate; easing back to neutral
    uses the decay rate. Switching sides ramps through neutral like a real
    wheel being spun.
    """

    __slots__ = ("value",)

    def __init__(self):
        self.value = 0.0

    def step(self, dt_ms, target, cfg):
        """Advance the ramp by dt_ms and return the shaped output."""
        if dt_ms > 0:
            rate = dt_ms / cfg.decay_ms if target == 0 else dt_ms / cfg.attack_ms
            if self.value < target:
                self.value = min(target, self.value + rate)
            elif self.value > target:
                self.value = max(target, self.value - rate)
            self.value = max(-1.0, min(1.0, self.value))
        return self.shape(self.value, cfg)

    @staticmethod
    def shape(v, cfg):
        """Map a raw ramp magnitude through the curve and anti-deadzone floor."""
        m = abs(v)
        m = 0.0 if m > 1.0 else m
        if cfg.curve == "linear":
            out = m
        elif cfg.curve == "aggressive":
            out = 0.0 if m <= 0 else 1.0 - (1.0 - m) * (1.0 - m)
        else:  # smooth (smoothstep)
            out = m * m * (3.0 - 2.0 * m)
        if 0.0 < out < cfg.anti_dz:
            out = cfg.anti_dz
        return -out if v < 0 else out

    def reset(self):
        self.value = 0.0
