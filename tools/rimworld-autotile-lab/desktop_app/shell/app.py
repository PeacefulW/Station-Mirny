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
WINDOW_TITLE = "Cliff Forge Desktop"
STATUS_BOOT = "Инициализация desktop-инструмента..."
STATUS_IDLE = "Ожидание"
STATS_EMPTY = "Сборка ещё не запускалась"
LABEL_AUTO_VARIANT = "Авто"
LABEL_VARIANT_PREFIX = "Вариант "
TEXT_PROCEDURAL = "процедурно"
TEXT_PREVIEW_EMPTY = "Превью ещё не собрано..."
TEXT_PREVIEW_HINT = "Колесо мыши: зум | ЛКМ: двигать"

PRESET_LABELS = {
    "mountain": "Гора",
    "wall": "Стена",
    "earth": "Грунт",
}
PRESET_KEYS_BY_LABEL = {label: key for key, label in PRESET_LABELS.items()}

PREVIEW_MODE_LABELS = {
    "composite": "Композит",
    "albedo": "Альбедо",
    "mask": "Маска",
    "height": "Высота",
    "normal": "Нормали",
}
PREVIEW_MODE_KEYS_BY_LABEL = {label: key for key, label in PREVIEW_MODE_LABELS.items()}

SLOT_LABELS = {
    "top": "Верх",
    "face": "Лицевая",
    "back": "Тыл",
    "base": "Основа",
}


class CliffForgeApp:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title(WINDOW_TITLE)
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
        self.preview_source_image: Image.Image | None = None
        self.preview_zoom = 1.0
        self.preview_offset_x = 0.0
        self.preview_offset_y = 0.0
        self.preview_drag_last: tuple[int, int] | None = None
        self.preview_render_size: tuple[int, int] | None = None

        self._build_variables()
        self._build_layout()
        self._bind_map_canvas()
        self._apply_preset("mountain", schedule=False)
        self._refresh_variant_selector()
        self._draw_map()
        self._set_status(STATUS_BOOT)

        self.root.after(120, self._poll_render_queue)
        self.request_render("full")

    def _build_variables(self) -> None:
        self.preset_var = tk.StringVar(value=PRESET_LABELS["mountain"])
        self.preview_mode_var = tk.StringVar(value=PREVIEW_MODE_LABELS["composite"])
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
        self.forced_variant_var = tk.StringVar(value=LABEL_AUTO_VARIANT)
        self.top_color_var = tk.StringVar(value="#705940")
        self.face_color_var = tk.StringVar(value="#3e2f25")
        self.back_color_var = tk.StringVar(value="#564436")
        self.base_color_var = tk.StringVar(value="#b88d58")
        self.stats_var = tk.StringVar(value=STATS_EMPTY)
        self.status_var = tk.StringVar(value=STATUS_IDLE)

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

        general = ttk.LabelFrame(self.sidebar_inner, text="Общие настройки", padding=10)
        general.pack(fill="x", pady=(0, 10))
        self._add_combo(
            general,
            "Пресет",
            self.preset_var,
            [PRESET_LABELS[key] for key in PRESETS.keys()],
            self._on_preset_changed,
        )
        self._add_combo(
            general,
            "Режим превью",
            self.preview_mode_var,
            [PREVIEW_MODE_LABELS[key] for key in PREVIEW_MODE_LABELS],
            lambda *_args: self.schedule_draft(),
        )
        self.variant_combo = self._add_combo(
            general,
            "Фиксированный вариант",
            self.forced_variant_var,
            [LABEL_AUTO_VARIANT, f"{LABEL_VARIANT_PREFIX}1", f"{LABEL_VARIANT_PREFIX}2", f"{LABEL_VARIANT_PREFIX}3", f"{LABEL_VARIANT_PREFIX}4"],
            lambda *_args: self.schedule_draft(),
        )

        seed_row = ttk.Frame(general)
        seed_row.pack(fill="x", pady=(8, 0))
        ttk.Label(seed_row, text="Сид").pack(side="left")
        seed_entry = ttk.Entry(seed_row, textvariable=self.seed_var, width=14)
        seed_entry.pack(side="left", padx=(8, 6))
        seed_entry.bind("<Return>", lambda _event: self.schedule_full())
        ttk.Button(seed_row, text="Случайный", command=self._randomize_seed).pack(side="left")

        shape = ttk.LabelFrame(self.sidebar_inner, text="Форма", padding=10)
        shape.pack(fill="x", pady=(0, 10))
        self._add_scale(shape, "Размер тайла", self.tile_size_var, 32, 96, 16, integer=True, full_on_release=True)
        self._add_scale(shape, "Южная высота", self.south_height_var, 4, 32, 1, integer=True)
        self._add_scale(shape, "Северная высота", self.north_height_var, 2, 24, 1, integer=True)
        self._add_scale(shape, "Боковая высота", self.side_height_var, 2, 24, 1, integer=True)
        self._add_scale(shape, "Шероховатость", self.roughness_var, 0, 100, 1)
        self._add_scale(shape, "Сила фасада", self.face_power_var, 0.4, 2.8, 0.05)
        self._add_scale(shape, "Задний спад", self.back_drop_var, 0.1, 0.8, 0.01)
        self._add_scale(shape, "Скос гребня", self.crown_bevel_var, 0, 12, 1, integer=True)
        self._add_scale(
            shape,
            "Число вариантов",
            self.variants_var,
            1,
            8,
            1,
            integer=True,
            callback=self._on_variant_count_changed,
            full_on_release=True,
        )
        self._add_scale(shape, "Масштаб текстуры", self.texture_scale_var, 0.25, 4.0, 0.05)

        colors = ttk.LabelFrame(self.sidebar_inner, text="Цвета", padding=10)
        colors.pack(fill="x", pady=(0, 10))
        self._add_color_row(colors, SLOT_LABELS["top"], self.top_color_var)
        self._add_color_row(colors, SLOT_LABELS["face"], self.face_color_var)
        self._add_color_row(colors, SLOT_LABELS["back"], self.back_color_var)
        self._add_color_row(colors, SLOT_LABELS["base"], self.base_color_var)

        textures = ttk.LabelFrame(self.sidebar_inner, text="Текстуры", padding=10)
        textures.pack(fill="x", pady=(0, 10))
        self.texture_labels = {}
        for slot in ("top", "face", "base"):
            row = ttk.Frame(textures)
            row.pack(fill="x", pady=3)
            ttk.Label(row, text=SLOT_LABELS[slot], width=10).pack(side="left")
            label = ttk.Label(row, text=TEXT_PROCEDURAL, width=24)
            label.pack(side="left", padx=(4, 6))
            ttk.Button(row, text="Загрузить", command=lambda s=slot: self._load_texture(s)).pack(side="left")
            ttk.Button(row, text="Сбросить", command=lambda s=slot: self._clear_texture(s)).pack(side="left", padx=(4, 0))
            self.texture_labels[slot] = label

        map_frame = ttk.LabelFrame(self.sidebar_inner, text="Карта", padding=10)
        map_frame.pack(fill="x", pady=(0, 10))
        self.map_canvas = tk.Canvas(map_frame, width=324, height=216, background="#161311", highlightthickness=1)
        self.map_canvas.pack()
        button_row = ttk.Frame(map_frame)
        button_row.pack(fill="x", pady=(8, 0))
        ttk.Button(button_row, text="Пятно", command=self._make_blob_map).pack(side="left")
        ttk.Button(button_row, text="Комната", command=self._make_room_map).pack(side="left", padx=(6, 0))
        ttk.Button(button_row, text="Пещера", command=self._make_cave_map).pack(side="left", padx=(6, 0))
        ttk.Button(button_row, text="Очистить", command=self._clear_map).pack(side="left", padx=(6, 0))

        actions = ttk.LabelFrame(self.sidebar_inner, text="Действия", padding=10)
        actions.pack(fill="x", pady=(0, 10))
        ttk.Button(actions, text="Черновое превью", command=self.schedule_draft).pack(fill="x")
        ttk.Button(actions, text="Полная сборка", command=self.schedule_full).pack(fill="x", pady=(6, 0))
        ttk.Button(actions, text="Экспорт файлов", command=self._export_outputs).pack(fill="x", pady=(6, 0))
        ttk.Button(actions, text="Сохранить рецепт", command=self._save_recipe).pack(fill="x", pady=(6, 0))
        ttk.Button(actions, text="Загрузить рецепт", command=self._load_recipe).pack(fill="x", pady=(6, 0))

        ttk.Label(self.sidebar_inner, textvariable=self.stats_var, justify="left").pack(fill="x", pady=(6, 0))

    def _build_content(self, parent: ttk.Frame) -> None:
        preview_frame = ttk.LabelFrame(parent, text="Превью", padding=12)
        preview_frame.grid(row=0, column=0, sticky="nsew", pady=(0, 10))
        preview_frame.columnconfigure(0, weight=1)
        preview_frame.rowconfigure(0, weight=1)
        self.preview_canvas = tk.Canvas(
            preview_frame,
            background="#171311",
            highlightthickness=0,
            takefocus=1,
        )
        self.preview_canvas.grid(row=0, column=0, sticky="nsew")
        self.preview_canvas.bind("<Configure>", lambda _event: self._render_preview_canvas())
        self.preview_canvas.bind("<Enter>", lambda _event: self.preview_canvas.focus_set())
        self.preview_canvas.bind("<MouseWheel>", self._on_preview_zoom)
        self.preview_canvas.bind("<Button-4>", self._on_preview_zoom)
        self.preview_canvas.bind("<Button-5>", self._on_preview_zoom)
        self.preview_canvas.bind("<ButtonPress-1>", self._start_preview_pan)
        self.preview_canvas.bind("<B1-Motion>", self._drag_preview_pan)
        self.preview_canvas.bind("<ButtonRelease-1>", self._end_preview_pan)
        self._render_preview_canvas()

        atlas_frame = ttk.LabelFrame(parent, text="Атлас", padding=12)
        atlas_frame.grid(row=1, column=0, sticky="nsew")
        atlas_frame.columnconfigure(0, weight=1)
        atlas_frame.rowconfigure(0, weight=1)
        self.atlas_label = ttk.Label(atlas_frame, anchor="center", text="Атлас ещё не собран...")
        self.atlas_label.grid(row=0, column=0, sticky="nsew")

    def _add_combo(self, parent: ttk.Widget, label: str, variable: tk.StringVar, values: list[str], callback) -> ttk.Combobox:
        row = ttk.Frame(parent)
        row.pack(fill="x", pady=(2, 6))
        ttk.Label(row, text=label, width=20).pack(side="left")
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
        ttk.Label(row, text=label, width=10).pack(side="left")
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
        self._apply_preset(self._selected_preset_key(), schedule=True)

    def _apply_preset(self, name: str, *, schedule: bool) -> None:
        preset = clone_preset(name)
        self.suspend_events = True
        try:
            self.preset_var.set(PRESET_LABELS.get(name, PRESET_LABELS["mountain"]))
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
        values = [LABEL_AUTO_VARIANT] + [f"{LABEL_VARIANT_PREFIX}{index + 1}" for index in range(total)]
        self.variant_combo.configure(values=values)
        if self.forced_variant_var.get() not in values:
            self.forced_variant_var.set(LABEL_AUTO_VARIANT)

    def _selected_preset_key(self) -> str:
        return PRESET_KEYS_BY_LABEL.get(self.preset_var.get(), "mountain")

    def _selected_preview_mode_key(self) -> str:
        return PREVIEW_MODE_KEYS_BY_LABEL.get(self.preview_mode_var.get(), "composite")

    def _randomize_seed(self) -> None:
        self.seed_var.set(random.randint(1, 2_147_483_647))
        self.schedule_full()

    def _load_texture(self, slot: str) -> None:
        file_path = filedialog.askopenfilename(
            title=f"Загрузить текстуру: {SLOT_LABELS[slot]}",
            filetypes=[("Изображения", "*.png;*.jpg;*.jpeg;*.bmp;*.webp"), ("Все файлы", "*.*")],
        )
        if not file_path:
            return
        self.texture_paths[slot] = file_path
        self.texture_labels[slot].configure(text=Path(file_path).name)
        self.schedule_full()

    def _clear_texture(self, slot: str) -> None:
        self.texture_paths[slot] = ""
        self.texture_labels[slot].configure(text=TEXT_PROCEDURAL)
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
        if self.forced_variant_var.get().startswith(LABEL_VARIANT_PREFIX):
            forced_variant = max(0, int(self.forced_variant_var.get().replace(LABEL_VARIANT_PREFIX, "", 1)) - 1)

        return {
            "preset": self._selected_preset_key(),
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
            "preview_mode": self._selected_preview_mode_key(),
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
        mode_label = "черновой" if mode == "draft" else "полный"
        self._set_status(f"Идёт {mode_label} рендер...")

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
            warning = f" Предупреждение: {warnings[0]}"
        self.stats_var.set(
            f"Сборка: {manifest.get('build_ms', '?')} мс\n"
            f"Сигнатуры: {manifest.get('signature_count', '?')}\n"
            f"Тайлы: {manifest.get('total_tiles', '?')}"
        )
        mode_value = manifest.get("mode", "render")
        mode_label = "Черновой" if mode_value == "draft" else "Полный" if mode_value == "full" else "Рендер"
        self._set_status(f"{mode_label} рендер завершён.{warning}")

        if self.pending_export_dir and manifest.get("mode") == "full":
            export_dir = self.pending_export_dir
            self.pending_export_dir = None
            self._copy_outputs_to(export_dir)

        if self.pending_mode:
            next_mode = self.pending_mode
            self.pending_mode = None
            self.request_render(next_mode)

    def _handle_error(self, error: Exception) -> None:
        self._set_status(f"Ошибка: {error}")
        messagebox.showerror(WINDOW_TITLE, str(error))
        if self.pending_mode:
            next_mode = self.pending_mode
            self.pending_mode = None
            self.request_render(next_mode)

    def _update_images(self, manifest: dict) -> None:
        files = manifest.get("files", {})
        preview_path = Path(files.get("preview_png", ""))
        if preview_path.exists():
            self._set_preview_image(preview_path)

        atlas_path = None
        mode = self._selected_preview_mode_key()
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
            self.atlas_label.configure(text="Черновой рендер готов. Запусти полную сборку, чтобы обновить атласы.")

    def _set_preview_image(self, path: Path) -> None:
        with Image.open(path) as image:
            self.preview_source_image = image.copy()
        self.preview_render_size = None
        self.photo_refs.pop("preview", None)
        self._render_preview_canvas()

    def _render_preview_canvas(self) -> None:
        if not hasattr(self, "preview_canvas"):
            return

        width = max(1, self.preview_canvas.winfo_width())
        height = max(1, self.preview_canvas.winfo_height())
        self.preview_canvas.delete("all")

        if self.preview_source_image is None:
            self.preview_canvas.create_text(
                width // 2,
                height // 2,
                text=f"{TEXT_PREVIEW_EMPTY}\n{TEXT_PREVIEW_HINT}",
                fill="#cdbca7",
                font=("Segoe UI", 13),
                justify="center",
            )
            return

        fit_scale = min(width / self.preview_source_image.width, height / self.preview_source_image.height)
        fit_scale = max(fit_scale, 0.01)
        scale = fit_scale * self.preview_zoom
        target_size = (
            max(1, int(round(self.preview_source_image.width * scale))),
            max(1, int(round(self.preview_source_image.height * scale))),
        )
        max_offset_x = max(0.0, (target_size[0] - width) / 2.0)
        max_offset_y = max(0.0, (target_size[1] - height) / 2.0)
        self.preview_offset_x = min(max(self.preview_offset_x, -max_offset_x), max_offset_x)
        self.preview_offset_y = min(max(self.preview_offset_y, -max_offset_y), max_offset_y)

        if self.preview_render_size != target_size or "preview" not in self.photo_refs:
            render_image = self.preview_source_image.resize(target_size, Image.Resampling.NEAREST)
            self.photo_refs["preview"] = ImageTk.PhotoImage(render_image)
            self.preview_render_size = target_size

        photo = self.photo_refs["preview"]
        self.preview_canvas.create_image(
            int(round(width / 2 + self.preview_offset_x)),
            int(round(height / 2 + self.preview_offset_y)),
            image=photo,
            anchor="center",
        )
        self.preview_canvas.create_text(
            12,
            12,
            text=f"Зум: {self.preview_zoom:.2f}x\nСмещение: {int(round(self.preview_offset_x))}, {int(round(self.preview_offset_y))}",
            fill="#f2e9dc",
            font=("Segoe UI", 10, "bold"),
            anchor="nw",
        )

    def _on_preview_zoom(self, event: tk.Event) -> str:
        if self.preview_source_image is None:
            return "break"

        delta = getattr(event, "delta", 0)
        if delta == 0 and getattr(event, "num", None) == 4:
            delta = 120
        elif delta == 0 and getattr(event, "num", None) == 5:
            delta = -120

        if delta == 0:
            return "break"

        zoom_step = 1.15 if delta > 0 else 1.0 / 1.15
        next_zoom = min(8.0, max(0.5, self.preview_zoom * zoom_step))
        if abs(next_zoom - self.preview_zoom) > 1e-6:
            self.preview_zoom = next_zoom
            self._render_preview_canvas()
        return "break"

    def _start_preview_pan(self, event: tk.Event) -> None:
        if self.preview_source_image is None:
            return
        self.preview_drag_last = (event.x, event.y)
        self.preview_canvas.configure(cursor="fleur")

    def _drag_preview_pan(self, event: tk.Event) -> str:
        if self.preview_source_image is None or self.preview_drag_last is None:
            return "break"

        last_x, last_y = self.preview_drag_last
        self.preview_offset_x += event.x - last_x
        self.preview_offset_y += event.y - last_y
        self.preview_drag_last = (event.x, event.y)
        self._render_preview_canvas()
        return "break"

    def _end_preview_pan(self, _event: tk.Event) -> None:
        self.preview_drag_last = None
        self.preview_canvas.configure(cursor="")

    def _set_image(self, widget: ttk.Label, path: Path, key: str, max_size: tuple[int, int]) -> None:
        with Image.open(path) as image:
            render_image = image.copy()
        render_image.thumbnail(max_size, Image.Resampling.NEAREST)
        photo = ImageTk.PhotoImage(render_image)
        widget.configure(image=photo, text="")
        self.photo_refs[key] = photo

    def _save_recipe(self) -> None:
        file_path = filedialog.asksaveasfilename(
            title="Сохранить рецепт",
            defaultextension=RECIPE_SUFFIX,
            filetypes=[("JSON", "*.json")],
        )
        if not file_path:
            return
        with open(file_path, "w", encoding="utf-8") as handle:
            json.dump(self.build_request(), handle, indent=2)
        self._set_status(f"Рецепт сохранён в {file_path}")

    def _load_recipe(self) -> None:
        file_path = filedialog.askopenfilename(
            title="Загрузить рецепт",
            filetypes=[("JSON", "*.json"), ("Все файлы", "*.*")],
        )
        if not file_path:
            return
        with open(file_path, "r", encoding="utf-8") as handle:
            payload = json.load(handle)

        request = payload.get("request", payload)
        self.suspend_events = True
        try:
            preset_key = request.get("preset", "mountain")
            self.preset_var.set(PRESET_LABELS.get(preset_key, PRESET_LABELS["mountain"]))
            self._apply_preset(preset_key, schedule=False)
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
            preview_key = request.get("preview_mode", self._selected_preview_mode_key())
            self.preview_mode_var.set(PREVIEW_MODE_LABELS.get(preview_key, PREVIEW_MODE_LABELS["composite"]))
            self._refresh_variant_selector()

            forced_variant = request.get("forced_variant")
            self.forced_variant_var.set(
                LABEL_AUTO_VARIANT
                if forced_variant is None
                else f"{LABEL_VARIANT_PREFIX}{int(forced_variant) + 1}"
            )

            colors = request.get("colors", {})
            self.top_color_var.set(colors.get("top", self.top_color_var.get()))
            self.face_color_var.set(colors.get("face", self.face_color_var.get()))
            self.back_color_var.set(colors.get("back", self.back_color_var.get()))
            self.base_color_var.set(colors.get("base", self.base_color_var.get()))

            textures = request.get("textures", {})
            for slot in ("top", "face", "base"):
                value = textures.get(slot) or ""
                self.texture_paths[slot] = value
                self.texture_labels[slot].configure(text=Path(value).name if value else TEXT_PROCEDURAL)

            map_payload = request.get("map")
            if map_payload:
                self.current_map = map_payload
                self._draw_map()
        finally:
            self.suspend_events = False

        self.schedule_full()

    def _export_outputs(self) -> None:
        target = filedialog.askdirectory(title="Экспорт файлов")
        if not target:
            return
        export_dir = Path(target)
        if not self.last_manifest or self.last_manifest.get("mode") != "full":
            self.pending_export_dir = export_dir
            self.schedule_full()
            self._set_status("Перед экспортом поставлена в очередь полная сборка...")
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
        self._set_status(f"Экспортировано {len(copied)} файл(ов) в {export_dir}")

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
