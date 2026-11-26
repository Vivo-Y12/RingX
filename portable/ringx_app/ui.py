"""Ringx tkinter UI: dashboard (wheel + pedals), mappings editor, settings.

Dark amber theme to match the Ringx identity. The after-loop drains the
keyboard hook, ticks the engine and redraws gauges at the profile tick rate.
"""

import math
import queue
import tkinter as tk
from tkinter import ttk

from . import __version__
from .engine import Engine
from .profile import (ACT_LABELS, ACTS, AXES, Binding, Profile, ProfileStore,
                      vk_name)

BG = "#0E1116"
CARD = "#16181D"
EDGE = "#2A2E36"
AMBER = "#F5A524"
GREEN = "#46A758"
RED = "#E5484D"
MUTED = "#7A8089"
FONT = ("Segoe UI", 10)
FONT_SM = ("Segoe UI", 9)
FONT_LG = ("Segoe UI", 12, "bold")

SAVE_DEBOUNCE_MS = 800


class RingxUI:
    def __init__(self, engine: Engine):
        self.engine = engine
        self._capturing = None  # callback for the next keydown, or None
        self._save_job = None

        self.root = tk.Tk()
        self.root.title(f"Ringx {__version__} — Keyboard Racing Controller")
        self.root.geometry("980x640")
        self.root.configure(bg=BG)
        self._style()

        self.notebook = ttk.Notebook(self.root)
        self.notebook.pack(fill="both", expand=True, padx=10, pady=10)
        self.notebook.add(self._tab_dashboard(), text=" Dashboard ")
        self.notebook.add(self._tab_mappings(), text=" Mappings ")
        self.notebook.add(self._tab_settings(), text=" Settings ")

        self.root.protocol("WM_DELETE_WINDOW", self._on_close)
        self._loop()

    # ---- theme -------------------------------------------------------------

    def _style(self):
        s = ttk.Style(self.root)
        try:
            s.theme_use("clam")
        except tk.TclError:
            pass
        s.configure(".", background=BG, foreground="#E7E9EE", font=FONT)
        s.configure("TNotebook", background=BG, borderwidth=0)
        s.configure("TNotebook.Tab", background=CARD, foreground=MUTED,
                    padding=(14, 7), font=FONT)
        s.map("TNotebook.Tab", background=[("selected", "#1E222A")],
              foreground=[("selected", AMBER)])
        s.configure("TButton", background=CARD, foreground="#E7E9EE",
                    borderwidth=1, relief="flat", padding=(12, 6))
        s.map("TButton", background=[("active", "#22262F")])
        s.configure("Accent.TButton", background=AMBER, foreground="#14161B")
        s.map("Accent.TButton", background=[("active", "#FFB84D")])
        s.configure("TCombobox", fieldbackground=CARD, background=CARD,
                    foreground="#E7E9EE", arrowcolor=MUTED)
        s.map("TCombobox", fieldbackground=[("readonly", CARD)])
        self.root.option_add("*TCombobox*Listbox.background", CARD)
        self.root.option_add("*TCombobox*Listbox.foreground", "#E7E9EE")
        self.root.option_add("*TCombobox*Listbox.selectBackground", "#2A2E36")
        s.configure("Horizontal.TScale", background=CARD, troughcolor=CARD)

    def _label(self, parent, text, **kw):
        fg = kw.pop("fg", "#E7E9EE")
        font = kw.pop("font", FONT)
        kw.setdefault("bg", BG)
        return tk.Label(parent, text=text, fg=fg, font=font, **kw)

    # ---- dashboard ---------------------------------------------------------

    def _tab_dashboard(self):
        tab = tk.Frame(self.root, bg=BG)
        top = tk.Frame(tab, bg=BG)
        top.pack(fill="x", padx=16, pady=(14, 4))
        self.lbl_hook = self._label(top, "", fg=MUTED, font=FONT_SM)
        self.lbl_hook.pack(side="left")
        self.lbl_vjoy = self._label(top, "", fg=MUTED, font=FONT_SM)
        self.lbl_vjoy.pack(side="left", padx=(16, 0))
        self.lbl_phone = self._label(top, "", fg=MUTED, font=FONT_SM)
        self.lbl_phone.pack(side="left", padx=(16, 0))
        self.lbl_axes = self._label(top, "", fg=MUTED, font=FONT_SM)
        self.lbl_axes.pack(side="right")

        mid = tk.Frame(tab, bg=BG)
        mid.pack(fill="both", expand=True, padx=16)
        self.canvas = tk.Canvas(mid, width=320, height=320, bg=BG,
                                highlightthickness=0)
        self.canvas.pack(side="left", padx=(10, 40), pady=6)
        self._build_wheel()

        pedals = tk.Frame(mid, bg=BG)
        pedals.pack(side="left", padx=10)
        self._build_pedal(pedals, "throttle", "THROTTLE", GREEN)
        self._build_pedal(pedals, "brake", "BRAKE", RED)

        right = tk.Frame(tab, bg=BG)
        right.pack(side="right", fill="y", padx=10)
        self.btn_toggle = ttk.Button(right, text="Mapping: OFF",
                                     style="Accent.TButton",
                                     command=self._toggle_mapping)
        self.btn_toggle.pack(pady=(16, 8))
        self.lbl_hotkey = self._label(right, "", fg=MUTED, font=FONT_SM)
        self.lbl_hotkey.pack()
        ttk.Button(right, text="Center & reset",
                   command=self.engine.center_reset).pack(pady=8)
        ttk.Button(right, text="Save profile",
                   command=self._save_now).pack(pady=8)
        self.lbl_save = self._label(right, "", fg=GREEN, font=FONT_SM)
        self.lbl_save.pack()

        bottom = tk.Frame(tab, bg=BG)
        bottom.pack(fill="x", padx=16, pady=(2, 12))
        self._label(bottom, "Recent keys", font=FONT_SM, fg=MUTED).pack(
            anchor="w")
        self.lbl_recent = self._label(bottom, "—", fg=MUTED, font=FONT_SM)
        self.lbl_recent.pack(anchor="w")
        return tab

    def _build_wheel(self):
        c = self.canvas
        cx = cy = 160
        self.w_ring = c.create_oval(18, 18, 302, 302, outline=EDGE, width=8)
        self.w_arc = c.create_arc(18, 18, 302, 302, start=90, extent=0,
                                  style="arc", outline=AMBER, width=8)
        self.w_rim = c.create_oval(48, 48, 272, 272, outline="#39404D",
                                   width=14)
        r = 112
        self.w_spokes = [c.create_line(cx, cy, cx, cy, width=12,
                                       capstyle="round", fill="#2C313B")
                         for _ in range(3)]
        self.w_hub = c.create_oval(cx - 20, cy - 20, cx + 20, cy + 20,
                                   fill=AMBER, outline="#12141A", width=3)
        self.w_text = c.create_text(cx, cy, text="CENTER", fill=BG,
                                    font=("Segoe UI", 11, "bold"))
        self._spoke_r = r
        self._cx = (cx, cy)

    def _build_pedal(self, parent, key, label, color):
        box = tk.Frame(parent, bg=BG)
        box.pack(side="left", padx=10)
        val = self._label(box, "0%", fg=color, font=FONT_LG)
        val.pack()
        cv = tk.Canvas(box, width=56, height=210, bg=BG, highlightthickness=0)
        cv.pack(pady=6)
        cv.create_rectangle(2, 2, 54, 208, fill=CARD, outline=EDGE)
        bar = cv.create_rectangle(4, 206, 52, 206, fill=color, outline="")
        self._label(box, label, fg=MUTED, font=FONT_SM).pack()
        setattr(self, f"ped_{key}_val", val)
        setattr(self, f"ped_{key}_bar", bar)
        setattr(self, f"ped_{key}_cv", cv)

    # ---- mappings ----------------------------------------------------------

    def _tab_mappings(self):
        tab = tk.Frame(self.root, bg=BG)
        head = tk.Frame(tab, bg=BG)
        head.pack(fill="x", padx=16, pady=(14, 4))
        self._label(head, "Bindings", font=FONT_LG).pack(side="left")
        ttk.Button(head, text="  Add binding  ",
                   command=self._add_binding).pack(side="right")

        self.listbox = tk.Listbox(tab, bg=CARD, fg="#E7E9EE",
                                  selectbackground=EDGE,
                                  selectforeground=AMBER, relief="flat",
                                  font=FONT, activestyle="none")
        self.listbox.pack(fill="both", expand=True, padx=16, pady=6)
        self.listbox.bind("<Double-Button-1>",
                          lambda e: self._edit_binding())

        btns = tk.Frame(tab, bg=BG)
        btns.pack(fill="x", padx=16)
        ttk.Button(btns, text="Edit", command=self._edit_binding).pack(
            side="left", padx=(0, 8))
        ttk.Button(btns, text="Remove", command=self._remove_binding).pack(
            side="left")
        self.lbl_dup = self._label(tab, "", fg=MUTED, font=FONT_SM)
        self.lbl_dup.pack(anchor="w", padx=16)

        tune = tk.Frame(tab, bg=BG)
        tune.pack(fill="x", padx=16, pady=(10, 12))
        self._label(tune, "Axis tuning (live — saves automatically)",
                    font=FONT_LG).pack(anchor="w")
        cards = tk.Frame(tune, bg=BG)
        cards.pack(fill="x")
        for axis in AXES:
            self._axis_card(cards, axis)
        self._refresh_bindings()
        return tab

    def _axis_card(self, parent, axis):
        title = {"steer": "Steering", "throttle": "Throttle",
                 "brake": "Brake"}[axis]
        card = tk.LabelFrame(parent, text=f"  {title}  ", bg=CARD, fg=MUTED,
                             font=FONT_SM, bd=1, relief="solid",
                             borderwidth=1, highlightcolor=EDGE)
        card.pack(side="left", fill="both", expand=True, padx=6)
        cfg = self.engine.profile.axes[axis]

        def scale(row, name, lo, hi, get, set_, fmt):
            tk.Label(card, text=name, bg=CARD, fg=MUTED,
                     font=FONT_SM).grid(row=row, column=0, sticky="w",
                                        padx=(10, 6), pady=3)
            var = tk.IntVar(value=get())
            out = tk.Label(card, text=fmt(get()), bg=CARD, fg="#E7E9EE",
                           font=FONT_SM, width=9, anchor="e")

            def on_change(v):
                set_(int(float(v)))
                out.config(text=fmt(get()))
                self._schedule_save()

            sc = ttk.Scale(card, from_=lo, to=hi, variable=var,
                           command=on_change)
            sc.grid(row=row, column=1, sticky="ew", padx=6)
            out.grid(row=row, column=2, padx=(0, 10))

        scale(0, "Attack", 10, 1000, lambda: cfg.attack_ms,
              lambda v: setattr(cfg, "attack_ms", v),
              lambda v: f"{v} ms")
        scale(1, "Decay", 10, 1000, lambda: cfg.decay_ms,
              lambda v: setattr(cfg, "decay_ms", v), lambda v: f"{v} ms")
        scale(2, "Anti-deadzone", 0, 25, lambda: round(cfg.anti_dz * 100),
              lambda v: setattr(cfg, "anti_dz", v / 100),
              lambda v: f"{v}%")

        curve_var = tk.StringVar(value=cfg.curve)
        cb = ttk.Combobox(card, textvariable=curve_var, state="readonly",
                          values=["linear", "smooth", "aggressive"],
                          width=11, font=FONT_SM)

        def on_curve(_e):
            cfg.curve = curve_var.get()
            self._schedule_save()

        cb.bind("<<ComboboxSelected>>", on_curve)
        tk.Label(card, text="Curve", bg=CARD, fg=MUTED,
                 font=FONT_SM).grid(row=3, column=0, sticky="w", padx=10,
                                    pady=3)
        cb.grid(row=3, column=1, sticky="w", padx=6, pady=(3, 8))
        card.columnconfigure(1, weight=1)

    def _refresh_bindings(self):
        lb = self.listbox
        lb.delete(0, tk.END)
        dups = set()
        seen = set()
        for b in self.engine.profile.bindings:
            label = vk_name(b.vk)
            action = ACT_LABELS[b.act]
            if b.act == "button":
                action += f" {b.button}"
            lb.insert(tk.END, f"  {label:<12} →  {action}")
            if b.vk in seen:
                dups.add(vk_name(b.vk))
            seen.add(b.vk)
        self.lbl_dup.config(
            text=f"Note: {' and '.join(sorted(dups))} bound more than once"
            if dups else "")

    def _add_binding(self):
        b = self._binding_dialog(None)
        if b is not None:
            self.engine.profile.bindings.append(b)
            self._after_profile_change()

    def _edit_binding(self):
        sel = self.listbox.curselection()
        if not sel:
            return
        i = sel[0]
        b = self._binding_dialog(self.engine.profile.bindings[i])
        if b is not None:
            self.engine.profile.bindings[i] = b
            self._after_profile_change()

    def _remove_binding(self):
        sel = self.listbox.curselection()
        if not sel:
            return
        del self.engine.profile.bindings[sel[0]]
        self._after_profile_change()

    def _after_profile_change(self):
        self._refresh_bindings()
        self._save_now()

    def _binding_dialog(self, initial):
        p = self.engine.profile
        b = initial
        state = {"vk": b.vk if b else 0}

        dlg = tk.Toplevel(self.root)
        dlg.title("Edit binding" if b else "Add binding")
        dlg.configure(bg=CARD)
        dlg.transient(self.root)
        dlg.resizable(False, False)
        dlg.grab_set()

        body = tk.Frame(dlg, bg=CARD)
        body.pack(padx=18, pady=14)

        def finish(result):
            dlg.result = result
            dlg.grab_release()
            dlg.destroy()

        # Key capture
        tk.Label(body, text="Key", bg=CARD, fg=MUTED,
                 font=FONT_SM).grid(row=0, column=0, sticky="w", pady=4)
        key_lbl = tk.Label(body, text=vk_name(state["vk"]) if state["vk"]
                           else "— none —", bg="#22262F", fg=AMBER,
                           font=FONT_LG, width=14)
        key_lbl.grid(row=0, column=1, sticky="w", padx=8, pady=4)

        def on_captured(vk):
            state["vk"] = vk
            key_lbl.config(text=vk_name(vk), fg=AMBER)

        def capture():
            key_lbl.config(text="press a key… (Esc cancels)", fg=MUTED)
            self._capturing = on_captured

        ttk.Button(body, text="Capture", command=capture).grid(
            row=0, column=2, padx=4)

        # Action
        tk.Label(body, text="Action", bg=CARD, fg=MUTED,
                 font=FONT_SM).grid(row=1, column=0, sticky="w", pady=4)
        act_var = tk.StringVar(value=ACT_LABELS[b.act if b else "steer_left"])
        act_cb = ttk.Combobox(body, textvariable=act_var, state="readonly",
                              values=[ACT_LABELS[a] for a in ACTS], width=16)
        act_cb.grid(row=1, column=1, sticky="w", padx=8, pady=4)

        btn_spin = [None]  # boxed so the closure below can replace it

        def refresh_spin():
            if act_var.get() == ACT_LABELS["button"]:
                if btn_spin[0] is None:
                    spin = ttk.Spinbox(body, from_=1, to=32, width=5,
                                       initialvalue=b.button if b else 1)
                    spin.grid(row=2, column=1, sticky="w", padx=8, pady=4)
                    tk.Label(body, text="Button number", bg=CARD, fg=MUTED,
                             font=FONT_SM).grid(row=2, column=0, sticky="w")
                    btn_spin[0] = spin
            elif btn_spin[0] is not None:
                btn_spin[0].destroy()
                btn_spin[0] = None

        act_cb.bind("<<ComboboxSelected>>", lambda e: refresh_spin())
        refresh_spin()

        note = tk.Label(body, text="", bg=CARD, fg=AMBER, font=FONT_SM)
        note.grid(row=3, column=0, columnspan=3, sticky="w", pady=(6, 0))
        warned = [False]

        def save():
            act_key = next(a for a in ACTS
                           if ACT_LABELS[a] == act_var.get())
            if state["vk"] == 0:
                note.config(text="Capture a key first.")
                return
            is_dup = (initial is None or state["vk"] != initial.vk) and any(
                x.vk == state["vk"] for x in p.bindings)
            if is_dup and not warned[0]:
                warned[0] = True
                note.config(text="That key is already bound — press Save "
                                 "again to allow it.")
                return
            n = 1
            if act_key == "button" and btn_spin[0] is not None:
                try:
                    n = max(1, min(32, int(btn_spin[0].get())))
                except ValueError:
                    pass
            finish(Binding(state["vk"], act_key, n))

        row = tk.Frame(dlg, bg=CARD)
        row.pack(pady=(0, 14))
        ttk.Button(row, text="  Save  ", style="Accent.TButton",
                   command=save).pack(side="left", padx=6)
        ttk.Button(row, text="Cancel",
                   command=lambda: finish(None)).pack(side="left", padx=6)
        self.root.wait_window(dlg)
        return dlg.result

    # ---- settings ----------------------------------------------------------

    def _tab_settings(self):
        tab = tk.Frame(self.root, bg=BG)
        frame = tk.LabelFrame(tab, text="  Device & engine  ", bg=CARD,
                              fg=MUTED, font=FONT_SM, bd=1, relief="solid")
        frame.pack(fill="x", padx=16, pady=(16, 8))

        tk.Label(frame, text="vJoy device", bg=CARD, fg="#E7E9EE",
                 font=FONT).grid(row=0, column=0, sticky="w", padx=12, pady=8)
        dev_var = tk.IntVar(value=self.engine.profile.device_id)
        dev_cb = ttk.Combobox(frame, textvariable=dev_var, state="readonly",
                              values=list(range(1, 17)), width=5)
        dev_cb.grid(row=0, column=1, sticky="w")
        dev_cb.bind("<<ComboboxSelected>>", lambda e: self._change_device(
            dev_var.get()))

        tk.Label(frame, text="Update rate", bg=CARD, fg="#E7E9EE",
                 font=FONT).grid(row=1, column=0, sticky="w", padx=12, pady=8)
        rate = {10: "100 Hz", 20: "50 Hz", 50: "20 Hz"}
        rate_var = tk.StringVar(value=rate[self.engine.profile.tick_ms])
        rate_cb = ttk.Combobox(frame, textvariable=rate_var, state="readonly",
                               values=list(rate.values()), width=8)
        rate_cb.grid(row=1, column=1, sticky="w")
        rev = {v: k for k, v in rate.items()}

        def on_rate(_e):
            self.engine.profile.tick_ms = rev[rate_var.get()]
            self._schedule_save()

        rate_cb.bind("<<ComboboxSelected>>", on_rate)

        tk.Label(frame, text="Toggle hotkey", bg=CARD, fg="#E7E9EE",
                 font=FONT).grid(row=2, column=0, sticky="w", padx=12, pady=8)
        hk_lbl = tk.Label(frame, text=vk_name(self.engine.profile.toggle_vk),
                          bg="#22262F", fg=AMBER, font=FONT_LG, width=10)
        hk_lbl.grid(row=2, column=1, sticky="w", pady=8)
        ttk.Button(frame, text="Change", command=lambda: self._capturing(
            self._set_hotkey(hk_lbl))).grid(row=2, column=2, padx=8)

        frame.columnconfigure(1, weight=1)

        phone = tk.LabelFrame(tab, text="  Phone controller  ", bg=CARD,
                              fg=MUTED, font=FONT_SM, bd=1, relief="solid")
        phone.pack(fill="x", padx=16, pady=8)
        self.chk_phone = tk.IntVar(
            value=1 if self.engine.profile.phone_enabled else 0)

        def on_phone_toggle():
            ok, err = self.engine.set_phone_enabled(
                bool(self.chk_phone.get()))
            if not ok:
                self.lbl_save.config(text=err or "Could not start the phone "
                                                 "server.", fg=RED)
            self._refresh_phone_labels()

        tk.Checkbutton(phone, text="Enable — use the phone as a wireless "
                                   "controller",
                       variable=self.chk_phone, command=on_phone_toggle,
                       bg=CARD, fg="#E7E9EE", activebackground=CARD,
                       activeforeground="#E7E9EE", selectcolor="#22262F",
                       font=FONT).pack(padx=12, pady=(10, 4), anchor="w")
        self.lbl_phone_status = self._label(phone, "", fg=MUTED, font=FONT_SM,
                                            bg=CARD)
        self.lbl_phone_status.pack(padx=12, anchor="w")
        self.lbl_phone_url = self._label(
            phone, "On the phone: open this in the browser\n"
                   "(both must be on the same Wi-Fi)",
            fg=MUTED, font=FONT_SM, bg=CARD, justify="left")
        self.lbl_phone_url.pack(padx=12, pady=(4, 10), anchor="w")
        self._refresh_phone_labels()

        prof = tk.LabelFrame(tab, text="  Profile  ", bg=CARD, fg=MUTED,
                             font=FONT_SM, bd=1, relief="solid")
        prof.pack(fill="x", padx=16, pady=8)
        path = self.engine.store.path
        tk.Label(prof, text=f"Stored at:  {path}", bg=CARD, fg=MUTED,
                 font=FONT_SM, anchor="w").pack(padx=12, pady=(10, 6),
                                                anchor="w")
        ttk.Button(prof, text="  Reset to racing defaults  ",
                   command=self._reset_defaults).pack(padx=12, pady=(0, 12),
                                                      anchor="w")
        tk.Label(tab, text=f"Ringx {__version__} — free, offline, no account. "
                           f"Turns your keyboard into a smooth virtual racing "
                           f"controller through vJoy.",
                 bg=BG, fg=MUTED, font=FONT_SM, wraplength=700,
                 justify="left").pack(padx=16, pady=8, anchor="w")
        return tab

    def _set_hotkey(self, label):
        def apply(vk):
            self.engine.profile.toggle_vk = vk
            label.config(text=vk_name(vk))
            self._schedule_save()
        return apply

    def _change_device(self, dev):
        p = Profile.from_dict(self.engine.profile.to_dict())
        p.device_id = dev
        ok, err = self.engine.apply_profile(p)
        if not ok:
            self.lbl_save.config(text=err or "Could not save profile.",
                                 fg=RED)
        self._refresh_bindings()

    def _reset_defaults(self):
        defaults = Profile.defaults()
        ok, err = self.engine.apply_profile(defaults)
        if not ok:
            self.lbl_save.config(text=err or "Could not save profile.",
                                 fg=RED)
        self.lbl_save.config(text="Reset to defaults — profile saved.",
                             fg=GREEN)
        self._refresh_bindings()
        self.root.after(2500, lambda: self.lbl_save.config(text=""))

    # ---- save / loop -------------------------------------------------------

    def _schedule_save(self):
        if self._save_job is not None:
            self.root.after_cancel(self._save_job)
        self._save_job = self.root.after(SAVE_DEBOUNCE_MS, self._save_now)

    def _save_now(self):
        self._save_job = None
        ok, err = self.engine.store.save(self.engine.profile)
        self.lbl_save.config(text="Profile saved ✓" if ok
                             else (err or "Save failed."),
                             fg=GREEN if ok else RED)
        self.root.after(2000, lambda: self.lbl_save.config(text=""))

    def _toggle_mapping(self):
        self.engine.set_enabled(not self.engine.enabled)

    def _loop(self):
        # Drain the hook queue; capture mode intercepts the next keydown.
        while True:
            try:
                vk, down = self.engine.hook.events.get_nowait()
            except queue.Empty:
                break
            if self._capturing is not None and down and vk != 0x1B:
                cb, self._capturing = self._capturing, None
                cb(vk)
            self.engine.on_key(vk, down)
        # Drain phone-link events (same pattern, one queue).
        link = self.engine.phone_link
        if link is not None:
            while True:
                try:
                    kind, payload = link.events.get_nowait()
                except queue.Empty:
                    break
                self.engine.on_phone_event(kind, payload)
                if kind in ("connect", "disconnect"):
                    self._refresh_phone_labels()
        self.engine.tick(self.engine.profile.tick_ms)
        self._refresh_dashboard()
        self.root.after(self.engine.profile.tick_ms, self._loop)

    def _refresh_phone_labels(self):
        """Settings-tab phone status + connect URLs."""
        link = self.engine.phone_link
        if link is None or not link.running:
            self.lbl_phone_status.config(
                text="Server off", fg=MUTED)
            self.lbl_phone_url.config(
                text="On the phone: open this in the browser\n"
                     "(both must be on the same Wi-Fi)")
            return
        urls = link.urls()
        self.lbl_phone_status.config(text=link.status_text(),
                                     fg=GREEN if link.connected else AMBER)
        self.lbl_phone_url.config(
            text="\n".join(urls) + "\n(both must be on the same Wi-Fi; "
            "allow Ringx in the Windows firewall)")

    def _refresh_dashboard(self):
        e = self.engine
        self.lbl_hook.config(
            text="● keyboard hook active" if e.hook_running
            else "● no keyboard hook (Windows only)",
            fg=GREEN if e.hook_running else RED)
        self.lbl_vjoy.config(text=f"● {e.note}", fg=GREEN if e.acquired
                             else (RED if e.vjoy is None else AMBER))
        link = e.phone_link
        if link is None or not link.running:
            phone_txt, phone_fg = "● phone link off", MUTED
        elif link.connected:
            phone_txt, phone_fg = "● phone connected", GREEN
        else:
            phone_txt, phone_fg = "● phone: waiting (see Settings)", AMBER
        self.lbl_phone.config(text=phone_txt, fg=phone_fg)
        self.lbl_axes.config(text=f"axes  {e.axis_summary()}")
        self.btn_toggle.config(text=f"Mapping: {'ON' if e.enabled else 'OFF'}")
        self.lbl_hotkey.config(
            text=f"hotkey: {vk_name(e.profile.toggle_vk)}")

        steer = e.steer_out
        self.canvas.itemconfigure(self.w_arc,
                                  extent=-steer * 270)
        self.canvas.itemconfigure(
            self.w_text,
            text="CENTER" if abs(steer) < 0.005
            else f"{'L' if steer < 0 else 'R'} {round(abs(steer) * 100)}%")
        ang = steer * 3.93
        cx, cy = self._cx
        for i, spoke in enumerate(self.w_spokes):
            a = math.radians(90 + i * 120 + math.degrees(ang))
            self.canvas.coords(spoke, cx, cy,
                               cx + self._spoke_r * math.cos(a),
                               cy + self._spoke_r * math.sin(a))

        for key, getter in (("throttle", e.throttle_out),
                            ("brake", e.brake_out)):
            v = max(0.0, min(1.0, getter))
            cv = getattr(self, f"ped_{key}_cv")
            bar = getattr(self, f"ped_{key}_bar")
            top = 6 + (202 - 202 * v)
            cv.coords(bar, 4, top, 52, 208)
            getattr(self, f"ped_{key}_val").config(
                text=f"{round(v * 100)}%")

        if e.recent_keys:
            self.lbl_recent.config(
                text="   ".join(vk_name(v) for v in e.recent_keys))

    def _on_close(self):
        self.engine.stop()
        self.root.destroy()

    def run(self):
        self.root.mainloop()
