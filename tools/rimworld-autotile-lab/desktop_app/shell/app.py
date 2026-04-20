from __future__ import annotations

import json
import queue
import random
import shutil
import threading
import tkinter as tk
from pathlib import Path
from tkinter import colorchooser, filedialog, messagebox, ttk

from PIL import Image, ImageTk

from core_bridge import DESKTOP_APP_DIR, run_core
from presets import PRESETS, clone_preset, make_blob_map, make_cave_map, make_room_map


SESSION_OUTPUT_DIR = DESKTOP_APP_DIR / "exports" / "session"
RECIPE_SUFFIX = ".json"


class CliffForgeApp:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("Cliff Forge Desktop")
        self.root.geometry("1560x980")
        self.root.minsize(1320, 860)

        self.render_queue: queue.Queue[tuple[str, object]] = queue.Queue()
        self.render_thread: threading.Thread | None = None
        self.pending_mode: str | None = None
        self.pending_export_dir: Path | None = None
        self.draft_after_id: str | None = None
        self.last_manifest: dict | None = None
        self.photo_refs: dict[str, ImageTk.PhotoImage] = {}
        self.suspend_events = False
        self.current_map = make_blob_map()
        self.texture_paths = {"top": "", "face": "", "base": ""}

        self._build_variables()
        self._build_layout()
        self._bind_map_canvas()
        self._apply_preset("mountain", schedule=False)
        self._refresh_variant_selector()
        self._draw_map()
        self._set_status("Инициализация нового desktop rewrite...")

        self.root.after(120, self._poll_render_queue)
        self.request_render("full")

    def _build_variables(self) -> None:
        self.preset_var = tk.StringVar(value="mountain")
        self.preview_mode_var = tk.StringVar(value="composite")
        self.seed_var = tk.IntVar(value=240_518)
        self.tile_size_var = tk.IntVar(value=64)
        self.south_height_var = tk.IntVar(value=18)
        self.north_height_var = tk.IntVar(value=10)
        self.side_height_var = tk.IntVar(value=16)
        self.roughness_var = tk.DoubleVar(value=52.0)
        self.face_power_var = tk.DoubleVar(value=1.0)
        self.back_drop_var = tk.DoubleVar(value=0.34)
        self.crown_bevel_var = tk.IntVar(value=2)
        self.variants_var = tk.IntVar(value=4)
        self.texture_scale_var = tk.DoubleVar(value=1.0)
        self.forced_variant_var = tk.StringVar(value="Auto")
        self.top_color_var = tk.StringVar(value="#705940")
        self.face_color_var = tk.StringVar(value="#3e2f25")
        self.back_color_var = tk.StringVar(value="#564436")
        self.base_color_var = tk.StringVar(value="#b88d58")
        self.stats_var = tk.StringVar(value="No build yet")
        self.status_var = tk.StringVar(value="Idle")

    def _build_layout(self) -> None:
        main = ttk.Frame(self.root, padding=12)
        main.pack(fill="both", expand=True)
        main.columnconfigure(1, weight=1)
        main.rowconfigure(0, weight=1)

        sidebar = ttk.Frame(main)
        sidebar.grid(row=0, column=0, sticky="nsw", padx=(0, 12))
        self._build_sidebar(sidebar)

        content = ttk.Frame(main)
        content.grid(row=0, column=1, sticky="nsew")
        content.columnconfigure(0, weight=1)
        content.rowconfigure(0, weight=1)
        content.rowconfigure(1, weight=1)
        self._build_content(content)

        status = ttk.Label(main, textvariable=self.status_var, anchor="w")
        status.grid(row=1, column=0, columnspan=2, sticky="ew", pady=(10, 0))

    def _build_sidebar(self, parent: ttk.Frame) -> None:
        canvas = tk.Canvas(parent, width=390, highlightthickness=0)
        scrollbar = ttk.Scrollbar(parent, orient="vertical", command=canvas.yview)
        canvas.configure(yscrollcommand=scrollbar.set)
        canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

        self.sidebar_inner = ttk.Frame(canvas, padding=(0, 0, 10, 0))
        canvas.create_window((0, 0), window=self.sidebar_inner, anchor="nw")
        self.sidebar_inner.bind(
            "<Configure>",
            lambda _event: canvas.configure(scrollregion=canvas.bbox("all")),
        )

        general = ttk.LabelFrame(self.sidebar_inner, text="General", padding=10)
        general.pack(fill="x", pady=(0, 10))
        self._add_combo(general, "Preset", self.preset_var, list(PRESETS.keys()), self._on_preset_changed)
        self._add_combo(
            general,
            "Preview Mode",
            self.preview_mode_var,
            ["composite", "albedo", "mask", "height", "normal"],
            lambda *_args: self.schedule_draft(),
        )
        self.variant_combo = self._add_combo(
            general,
            "Forced Variant",
            self.forced_variant_var,
            ["Auto", "v1", "v2", "v3", "v4"],
            lambda *_args: self.schedule_draft(),
        )

        seed_row = ttk.Frame(general)
        seed_row.pack(fill="x", pady=(8, 0))
        ttk.Label(seed_row, text="Seed").pack(side="left")
        seed_entry = ttk.Entry(seed_row, textvariable=self.seed_var, width=14)
        seed_entry.pack(side="left", padx=(8, 6))
        seed_entry.bind("<Return>", lambda _event: self.schedule_full())
        ttk.Button(seed_row, text="Randomize", command=self._randomize_seed).pack(side="left")

        shape = ttk.LabelFrame(self.sidebar_inner, text="Shape", padding=10)
        shape.pack(fill="x", pady=(0, 10))
        self._add_scale(shape, "Tile Size", self.tile_size_var, 32, 96, 16, integer=True, full_on_release=True)
        self._add_scale(shape, "South Height", self.south_height_var, 4, 32, 1, integer=True)
        self._add_scale(shape, "North Height", self.north_height_var, 2, 24, 1, integer=True)
        self._add_scale(shape, "Side Height", self.side_height_var, 2, 24, 1, integer=True)
        self._add_scale(shape, "Roughness", self.roughness_var, 0, 100, 1)
        self._add_scale(shape, "Face Power", self.face_power_var, 0.4, 2.8, 0.05)
        self._add_scale(shape, "Back Drop", self.back_drop_var, 0.1, 0.8, 0.01)
        self._add_scale(shape, "Crown Bevel", self.crown_bevel_var, 0, 12, 1, integer=True)
        self._add_scale(
            shape,
            "Variant Count",
            self.variants_var,
            1,
            8,
            1,
            integer=True,
            callback=self._on_variant_count_changed,
            full_on_release=True,
        )
        self._add_scale(shape, "Texture Scale", self.texture_scale_var, 0.25, 4.0, 0.05)

        colors = ttk.LabelFrame(self.sidebar_inner, text="Colors", padding=10)
        colors.pack(fill="x", pady=(0, 10))
        self._add_color_row(colors, "Top", self.top_color_var)
        self._add_color_row(colors, "Face", self.face_color_var)
        self._add_color_row(colors, "Back", self.back_color_var)
        self._add_color_row(colors, "Base", self.base_color_var)

        textures = ttk.LabelFrame(self.sidebar_inner, text="Textures", padding=10)
        textures.pack(fill="x", pady=(0, 10))
        self.texture_labels = {}
        for slot in ("top", "face", "base"):
            row = ttk.Frame(textures)
            row.pack(fill="x", pady=3)
            ttk.Label(row, text=slot.title(), width=6).pack(side="left")
            label = ttk.Label(row, text="procedural", width=24)
            label.pack(side="left", padx=(4, 6))
            ttk.Button(row, text="Load", command=lambda s=slot: self._load_texture(s)).pack(side="left")
            ttk.Button(row, text="Clear", command=lambda s=slot: self._clear_texture(s)).pack(side="left", padx=(4, 0))
            self.texture_labels[slot] = label

        map_frame = ttk.LabelFrame(self.sidebar_inner, text="Map", padding=10)
        map_frame.pack(fill="x", pady=(0, 10))
        self.map_canvas = tk.Canvas(map_frame, width=324, height=216, background="#161311", highlightthickness=1)
        self.map_canvas.pack()
        button_row = ttk.Frame(map_frame)
        button_row.pack(fill="x", pady=(8, 0))
        ttk.Button(button_row, text="Blob", command=self._make_blob_map).pack(side="left")
        ttk.Button(button_row, text="Room", command=self._make_room_map).pack(side="left", padx=(6, 0))
        ttk.Button(button_row, text="Cave", command=self._make_cave_map).pack(side="left", padx=(6, 0))
        ttk.Button(button_row, text="Clear", command=self._clear_map).pack(side="left", padx=(6, 0))

        actions = ttk.LabelFrame(self.sidebar_inner, text="Actions", padding=10)
        actions.pack(fill="x", pady=(0, 10))
        ttk.Button(actions, text="Draft Preview", command=self.schedule_draft).pack(fill="x")
        ttk.Button(actions, text="Full Generate", command=self.schedule_full).pack(fill="x", pady=(6, 0))
        ttk.Button(actions, text="Export Outputs", command=self._export_outputs).pack(fill="x", pady=(6, 0))
        ttk.Button(actions, text="Save Recipe", command=self._save_recipe).pack(fill="x", pady=(6, 0))
        ttk.Button(actions, text="Load Recipe", command=self._load_recipe).pack(fill="x", pady=(6, 0))

        ttk.Label(self.sidebar_inner, textvariable=self.stats_var, justify="left").pack(fill="x", pady=(6, 0))

    def _build_content(self, parent: ttk.Frame) -> None:
        preview_frame = ttk.LabelFrame(parent, text="Preview", padding=12)
        preview_frame.grid(row=0, column=0, sticky="nsew", pady=(0, 10))
        preview_frame.columnconfigure(0, weight=1)
        preview_frame.rowconfigure(0, weight=1)
        self.preview_label = ttk.Label(preview_frame, anchor="center", text="Preview pending...")
        self.preview_label.grid(row=0, column=0, sticky="nsew")

        atlas_frame = ttk.LabelFrame(parent, text="Atlas", padding=12)
        atlas_frame.grid(row=1, column=0, sticky="nsew")
        atlas_frame.columnconfigure(0, weight=1)
        atlas_frame.rowconfigure(0, weight=1)
        self.atlas_label = ttk.Label(atlas_frame, anchor="center", text="Atlas pending...")
        self.atlas_label.grid(row=0, column=0, sticky="nsew")

    def _add_combo(self, parent: ttk.Widget, label: str, variable: tk.StringVar, values: list[str], callback) -> ttk.Combobox:
        row = ttk.Frame(parent)
        row.pack(fill="x", pady=(2, 6))
        ttk.Label(row, text=label, width=14).pack(side="left")
        combo = ttk.Combobox(row, textvariable=variable, values=values, state="readonly", width=18)
        combo.pack(side="left", fill="x", expand=True)
        combo.bind("<<ComboboxSelected>>", callback)
        return combo

    def _add_scale(
        self,
        parent: ttk.Widget,
        label: str,
        variable: tk.Variable,
        start: float,
        end: float,
        resolution: float,
        *,
        integer: bool = False,
        callback=None,
        full_on_release: bool = False,
    ) -> None:
        frame = ttk.Frame(parent)
        frame.pack(fill="x", pady=(2, 6))
        value_label = ttk.Label(frame, text=self._format_var(variable), width=8)
        value_label.pack(side="right")
        ttk.Label(frame, text=label).pack(side="left")

        scale = tk.Scale(
            parent,
            from_=start,
            to=end,
            orient="horizontal",
            resolution=resolution,
            variable=variable,
            showvalue=False,
            command=lambda _value, var=variable, out=value_label: self._on_scale_change(var, out),
        )
        scale.pack(fill="x")
        scale.bind("<ButtonRelease-1>", lambda _event: self.schedule_full() if full_on_release else self.schedule_draft())
        if callback:
            scale.bind("<ButtonRelease-1>", lambda _event, cb=callback: cb(), add="+")

    def _add_color_row(self, parent: ttk.Widget, label: str, variable: tk.StringVar) -> None:
        row = ttk.Frame(parent)
        row.pack(fill="x", pady=3)
        ttk.Label(row, text=label, width=6).pack(side="left")
        entry = ttk.Entry(row, textvariable=variable, width=12)
        entry.pack(side="left", padx=(4, 6))
        entry.bind("<Return>", lambda _event: self.schedule_full())
        button = tk.Button(
            row,
            width=3,
            relief="flat",
            background=variable.get(),
            command=lambda var=variable: self._pick_color(var),
        )
        button.pack(side="left")
        variable.trace_add("write", lambda *_args, btn=button, var=variable: self._sync_color_button(btn, var))

    def _sync_color_button(self, button: tk.Button, variable: tk.StringVar) -> None:
        button.configure(background=variable.get())
        if not self.suspend_events:
            self.schedule_draft()

    def _pick_color(self, variable: tk.StringVar) -> None:
        _, hex_value = colorchooser.askcolor(color=variable.get(), parent=self.root)
        if hex_value:
            variable.set(hex_value)
            self.schedule_full()

    def _format_var(self, variable: tk.Variable) -> str:
        value = variable.get()
        if isinstance(value, float):
            return f"{value:.2f}"
        return str(value)

    def _on_scale_change(self, variable: tk.Variable, label: ttk.Label) -> None:
        label.configure(text=self._format_var(variable))
        self.schedule_draft()

    def _bind_map_canvas(self) -> None:
        self._paint_mode = 1

        def start_paint(event: tk.Event, value: int) -> None:
            self._paint_mode = value
            self._apply_paint(event)

        self.map_canvas.bind("<Button-1>", lambda event: start_paint(event, 1))
        self.map_canvas.bind("<B1-Motion>", self._apply_paint)
        self.map_canvas.bind("<Button-3>", lambda event: start_paint(event, 0))
        self.map_canvas.bind("<B3-Motion>", self._apply_paint)
        self.map_canvas.bind("<ButtonRelease-1>", lambda _event: self.schedule_full())
        self.map_canvas.bind("<ButtonRelease-3>", lambda _event: self.schedule_full())

    def _apply_paint(self, event: tk.Event) -> None:
        cell_size = 18
        x = max(0, min(self.current_map["width"] - 1, event.x // cell_size))
        y = max(0, min(self.current_map["height"] - 1, event.y // cell_size))
        index = y * self.current_map["width"] + x
        self.current_map["cells"][index] = self._paint_mode
        self._draw_map()
        self.schedule_draft()

    def _draw_map(self) -> None:
        self.map_canvas.delete("all")
        cell_size = 18
        for y in range(self.current_map["height"]):
            for x in range(self.current_map["width"]):
                index = y * self.current_map["width"] + x
                filled = self.current_map["cells"][index] > 0
                left = x * cell_size
                top = y * cell_size
                self.map_canvas.create_rectangle(
                    left,
                    top,
                    left + cell_size,
                    top + cell_size,
                    fill="#c58f55" if filled else "#201917",
                    outline="#3b2f29",
                )

    def _on_preset_changed(self, *_args) -> None:
        self._apply_preset(self.preset_var.get(), schedule=True)

    def _apply_preset(self, name: str, *, schedule: bool) -> None:
        preset = clone_preset(name)
        self.suspend_events = True
        try:
            self.preset_var.set(name)
            self.tile_size_var.set(preset["tile_size"])
            self.south_height_var.set(preset["south_height"])
            self.north_height_var.set(preset["north_height"])
            self.side_height_var.set(preset["side_height"])
            self.roughness_var.set(preset["roughness"])
            self.face_power_var.set(preset["face_power"])
            self.back_drop_var.set(preset["back_drop"])
            self.crown_bevel_var.set(preset["crown_bevel"])
            self.variants_var.set(preset["variants"])
            self.texture_scale_var.set(preset["texture_scale"])
            self.top_color_var.set(preset["colors"]["top"])
            self.face_color_var.set(preset["colors"]["face"])
            self.back_color_var.set(preset["colors"]["back"])
            self.base_color_var.set(preset["colors"]["base"])
        finally:
            self.suspend_events = False
        self._refresh_variant_selector()
        if schedule:
            self.schedule_full()

    def _on_variant_count_changed(self) -> None:
        self._refresh_variant_selector()
        self.schedule_full()

    def _refresh_variant_selector(self) -> None:
        total = max(1, int(self.variants_var.get()))
        values = ["Auto"] + [f"v{index + 1}" for index in range(total)]
        self.variant_combo.configure(values=values)
        if self.forced_variant_var.get() not in values:
            self.forced_variant_var.set("Auto")

    def _randomize_seed(self) -> None:
        self.seed_var.set(random.randint(1, 2_147_483_647))
        self.schedule_full()

    def _load_texture(self, slot: str) -> None:
        file_path = filedialog.askopenfilename(
            title=f"Load {slot} texture",
            filetypes=[("Images", "*.png;*.jpg;*.jpeg;*.bmp;*.webp"), ("All files", "*.*")],
        )
        if not file_path:
            return
        self.texture_paths[slot] = file_path
        self.texture_labels[slot].configure(text=Path(file_path).name)
        self.schedule_full()

    def _clear_texture(self, slot: str) -> None:
        self.texture_paths[slot] = ""
        self.texture_labels[slot].configure(text="procedural")
        self.schedule_full()

    def _make_blob_map(self) -> None:
        self.current_map = make_blob_map()
        self._draw_map()
        self.schedule_full()

    def _make_room_map(self) -> None:
        self.current_map = make_room_map()
        self._draw_map()
        self.schedule_full()

    def _make_cave_map(self) -> None:
        self.current_map = make_cave_map(int(self.seed_var.get()))
        self._draw_map()
        self.schedule_full()

    def _clear_map(self) -> None:
        self.current_map = {"width": 18, "height": 12, "cells": [0] * (18 * 12)}
        self._draw_map()
        self.schedule_full()

    def build_request(self) -> dict:
        forced_variant = None
        if self.forced_variant_var.get().startswith("v"):
            forced_variant = max(0, int(self.forced_variant_var.get()[1:]) - 1)

        return {
            "preset": self.preset_var.get(),
            "tile_size": int(self.tile_size_var.get()),
            "south_height": int(self.south_height_var.get()),
            "north_height": int(self.north_height_var.get()),
            "side_height": int(self.side_height_var.get()),
            "roughness": float(self.roughness_var.get()),
            "face_power": float(self.face_power_var.get()),
            "back_drop": float(self.back_drop_var.get()),
            "crown_bevel": int(self.crown_bevel_var.get()),
            "variants": int(self.variants_var.get()),
            "forced_variant": forced_variant,
            "seed": int(self.seed_var.get()),
            "texture_scale": float(self.texture_scale_var.get()),
            "preview_mode": self.preview_mode_var.get(),
            "textures": {
                "top": self.texture_paths["top"] or None,
                "face": self.texture_paths["face"] or None,
                "base": self.texture_paths["base"] or None,
            },
            "colors": {
                "top": self.top_color_var.get(),
                "face": self.face_color_var.get(),
                "back": self.back_color_var.get(),
                "base": self.base_color_var.get(),
            },
            "map": self.current_map,
        }

    def schedule_draft(self) -> None:
        if self.draft_after_id:
            self.root.after_cancel(self.draft_after_id)
        self.draft_after_id = self.root.after(180, lambda: self.request_render("draft"))

    def schedule_full(self) -> None:
        if self.draft_after_id:
            self.root.after_cancel(self.draft_after_id)
            self.draft_after_id = None
        self.request_render("full")

    def request_render(self, mode: str) -> None:
        if self.render_thread and self.render_thread.is_alive():
            self.pending_mode = self._merge_modes(self.pending_mode, mode)
            return

        self.draft_after_id = None
        request = self.build_request()
        self._set_status(f"Running {mode} render...")

        def worker() -> None:
            try:
                manifest = run_core(mode, request, SESSION_OUTPUT_DIR)
                self.render_queue.put(("ok", manifest))
            except Exception as error:  # noqa: BLE001
                self.render_queue.put(("error", error))

        self.render_thread = threading.Thread(target=worker, daemon=True)
        self.render_thread.start()

    def _merge_modes(self, existing: str | None, incoming: str) -> str:
        if existing == "full" or incoming == "full":
            return "full"
        return incoming

    def _poll_render_queue(self) -> None:
        try:
            while True:
                status, payload = self.render_queue.get_nowait()
                if status == "ok":
                    self._handle_manifest(payload)
                else:
                    self._handle_error(payload)
        except queue.Empty:
            pass
        finally:
            self.root.after(120, self._poll_render_queue)

    def _handle_manifest(self, manifest: dict) -> None:
        self.last_manifest = manifest
        self._update_images(manifest)
        warning = ""
        warnings = manifest.get("warnings") or []
        if warnings:
            warning = f" Warning: {warnings[0]}"
        self.stats_var.set(
            f"Build: {manifest.get('build_ms', '?')} ms\n"
            f"Signatures: {manifest.get('signature_count', '?')}\n"
            f"Tiles: {manifest.get('total_tiles', '?')}"
        )
        self._set_status(f"{manifest.get('mode', 'render')} render complete.{warning}")

        if self.pending_export_dir and manifest.get("mode") == "full":
            export_dir = self.pending_export_dir
            self.pending_export_dir = None
            self._copy_outputs_to(export_dir)

        if self.pending_mode:
            next_mode = self.pending_mode
            self.pending_mode = None
            self.request_render(next_mode)

    def _handle_error(self, error: Exception) -> None:
        self._set_status(f"Error: {error}")
        messagebox.showerror("Cliff Forge Desktop", str(error))
        if self.pending_mode:
            next_mode = self.pending_mode
            self.pending_mode = None
            self.request_render(next_mode)

    def _update_images(self, manifest: dict) -> None:
        files = manifest.get("files", {})
        preview_path = Path(files.get("preview_png", ""))
        if preview_path.exists():
            self._set_image(self.preview_label, preview_path, "preview", (980, 430))

        atlas_path = None
        mode = self.preview_mode_var.get()
        if mode in ("composite", "albedo"):
            atlas_value = files.get("atlas_albedo_png")
        elif mode == "mask":
            atlas_value = files.get("atlas_mask_png")
        elif mode == "height":
            atlas_value = files.get("atlas_height_png")
        else:
            atlas_value = files.get("atlas_normal_png")

        if atlas_value:
            atlas_path = Path(atlas_value)
        if atlas_path and atlas_path.exists():
            self._set_image(self.atlas_label, atlas_path, "atlas", (980, 430))
        elif manifest.get("mode") == "draft":
            self.atlas_label.configure(text="Draft complete. Run Full Generate to refresh atlases.")

    def _set_image(self, widget: ttk.Label, path: Path, key: str, max_size: tuple[int, int]) -> None:
        image = Image.open(path)
        image.thumbnail(max_size, Image.Resampling.NEAREST)
        photo = ImageTk.PhotoImage(image)
        widget.configure(image=photo, text="")
        self.photo_refs[key] = photo

    def _save_recipe(self) -> None:
        file_path = filedialog.asksaveasfilename(
            title="Save Recipe",
            defaultextension=RECIPE_SUFFIX,
            filetypes=[("JSON", "*.json")],
        )
        if not file_path:
            return
        with open(file_path, "w", encoding="utf-8") as handle:
            json.dump(self.build_request(), handle, indent=2)
        self._set_status(f"Recipe saved to {file_path}")

    def _load_recipe(self) -> None:
        file_path = filedialog.askopenfilename(
            title="Load Recipe",
            filetypes=[("JSON", "*.json"), ("All files", "*.*")],
        )
        if not file_path:
            return
        with open(file_path, "r", encoding="utf-8") as handle:
            payload = json.load(handle)

        request = payload.get("request", payload)
        self.suspend_events = True
        try:
            self.preset_var.set(request.get("preset", "mountain"))
            self._apply_preset(self.preset_var.get(), schedule=False)
            self.tile_size_var.set(int(request.get("tile_size", self.tile_size_var.get())))
            self.south_height_var.set(int(request.get("south_height", self.south_height_var.get())))
            self.north_height_var.set(int(request.get("north_height", self.north_height_var.get())))
            self.side_height_var.set(int(request.get("side_height", self.side_height_var.get())))
            self.roughness_var.set(float(request.get("roughness", self.roughness_var.get())))
            self.face_power_var.set(float(request.get("face_power", self.face_power_var.get())))
            self.back_drop_var.set(float(request.get("back_drop", self.back_drop_var.get())))
            self.crown_bevel_var.set(int(request.get("crown_bevel", self.crown_bevel_var.get())))
            self.variants_var.set(int(request.get("variants", self.variants_var.get())))
            self.seed_var.set(int(request.get("seed", self.seed_var.get())))
            self.texture_scale_var.set(float(request.get("texture_scale", self.texture_scale_var.get())))
            self.preview_mode_var.set(request.get("preview_mode", self.preview_mode_var.get()))
            self._refresh_variant_selector()

            forced_variant = request.get("forced_variant")
            self.forced_variant_var.set("Auto" if forced_variant is None else f"v{int(forced_variant) + 1}")

            colors = request.get("colors", {})
            self.top_color_var.set(colors.get("top", self.top_color_var.get()))
            self.face_color_var.set(colors.get("face", self.face_color_var.get()))
            self.back_color_var.set(colors.get("back", self.back_color_var.get()))
            self.base_color_var.set(colors.get("base", self.base_color_var.get()))

            textures = request.get("textures", {})
            for slot in ("top", "face", "base"):
                value = textures.get(slot) or ""
                self.texture_paths[slot] = value
                self.texture_labels[slot].configure(text=Path(value).name if value else "procedural")

            map_payload = request.get("map")
            if map_payload:
                self.current_map = map_payload
                self._draw_map()
        finally:
            self.suspend_events = False

        self.schedule_full()

    def _export_outputs(self) -> None:
        target = filedialog.askdirectory(title="Export Outputs")
        if not target:
            return
        export_dir = Path(target)
        if not self.last_manifest or self.last_manifest.get("mode") != "full":
            self.pending_export_dir = export_dir
            self.schedule_full()
            self._set_status("Full generate queued before export...")
            return
        self._copy_outputs_to(export_dir)

    def _copy_outputs_to(self, export_dir: Path) -> None:
        export_dir.mkdir(parents=True, exist_ok=True)
        files = self.last_manifest.get("files", {}) if self.last_manifest else {}
        copied = []
        for value in files.values():
            if not value:
                continue
            source = Path(value)
            if source.exists():
                destination = export_dir / source.name
                shutil.copy2(source, destination)
                copied.append(destination.name)
        self._set_status(f"Exported {len(copied)} file(s) to {export_dir}")

    def _set_status(self, text: str) -> None:
        self.status_var.set(text)


def main() -> None:
    root = tk.Tk()
    style = ttk.Style(root)
    if "vista" in style.theme_names():
        style.theme_use("vista")
    CliffForgeApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
