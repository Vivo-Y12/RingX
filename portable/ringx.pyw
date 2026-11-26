"""Ringx launcher — double-click this file (runs with pythonw, no console).

Original clean-room implementation; no code from any other product.
"""

import os
import sys
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def main():
    from ringx_app.engine import Engine
    from ringx_app.profile import ProfileStore
    from ringx_app.ui import RingxUI
    from ringx_app.wsserver import PhoneLink

    store = ProfileStore()
    profile, load_err = store.load()

    engine = Engine(store, profile)
    engine.phone_link = PhoneLink()
    engine.start()
    if load_err and engine.note:
        engine.note = f"{engine.note} ({load_err})"
    elif load_err:
        engine.note = load_err

    ui = RingxUI(engine)
    ui.run()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # No console under pythonw: dump details next to the app, then show
        # a dialog so the error can be reported back.
        log = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "ringx-error.log")
        try:
            with open(log, "w", encoding="utf-8") as f:
                f.write(traceback.format_exc())
        except OSError:
            pass
        try:
            import tkinter as tk
            from tkinter import messagebox
            root = tk.Tk()
            root.withdraw()
            messagebox.showerror(
                "Ringx failed to start",
                "Something went wrong.\nDetails were written to:\n"
                f"{log}\n\nSend that file for a quick fix.")
        except Exception:
            pass
        raise
