"""Cliff Forge Desktop — UI shell."""
from __future__ import annotations

import json
import queue
import random
import shutil
import threading
import tkinter as tk
from collections import deque
from pathlib import Path
from tkinter import colorchooser, filedialog, messagebox, ttk

from PIL import Image, ImageTk

from core_bridge import DESKTOP_APP_DIR, run_core
from presets import PRESETS, clone_preset, make_blob_map, make_cave_map, make_room_map


# ─── Paths & limits ──────────────────────────────────────────────────────────

SESSION_OUTPUT_DIR = DESKTOP_APP_DIR / "exports" / "session"
STATE_FILE = DESKTOP_APP_DIR / ".ui_state.json"
RECIPE_SUFFIX = ".json"

WINDOW_TITLE = "Cliff Forge Desktop"
DEFAULT_GEOMETRY = "1640x1000"
MIN_SIZE = (1280, 760)

MAP_HISTORY_LIMIT = 32
RECENT_COLORS_LIMIT = 12
RECENT_RECIPES_LIMIT = 6
MAP_W_RANGE = (8, 32)
MAP_H_RANGE = (6, 24)
MAP_DEFAULT_W = 18
MAP_DEFAULT_H = 12


# ─── Theme ───────────────────────────────────────────────────────────────────

THEME = {
    "bg":         "#1d1c1a",
    "panel":      "#262421",
    "panel_alt":  "#2c2a26",
    "input":      "#322f2a",
    "border":     "#3d362d",
    "fg":         "#e0d4bd",
    "fg_dim":     "#9b907c",
    "accent":     "#c58f55",
    "accent_dim": "#7d5a36",
    "warn":       "#d68a3a",
    "danger":     "#c75a4f",
    "ok":         "#7da45a",
    "map_fill":   "#c58f55",
    "map_empty":  "#1a1715",
    "map_grid":   "#3a3128",
    "map_hover":  "#4f4537",
}


# ─── Labels ──────────────────────────────────────────────────────────────────

STATUS_BOOT = "Инициализация..."
STATUS_IDLE = "Ожидание"
STATS_EMPTY = "Сборка ещё не запускалась"
LABEL_AUTO_VARIANT = "Авто"
LABEL_VARIANT_PREFIX = "Вариант "
TEXT_PROCEDURAL = "процедурно"
TEXT_PREVIEW_EMPTY = "Превью ещё не собрано"
TEXT_PREVIEW_HINT = "Колесо мыши: зум | ЛКМ: тянуть"
TEXT_TEXTURE_COLOR_OVERLAY = "Накладывать цвета на загруженные текстуры"

PRESET_LABELS = {
    "mountain": "Гора",
    "wall":     "Стена",
    "earth":    "Грунт",
}
PRESET_KEYS_BY_LABEL = {label: key for key, label in PRESET_LABELS.items()}

PREVIEW_MODE_LABELS = {
    "composite": "Композит",
    "albedo":    "Альбедо",
    "mask":      "Маска",
    "height":    "Высота",
    "normal":    "Нормали",
}
PREVIEW_MODE_KEYS_BY_LABEL = {label: key for key, label in PREVIEW_MODE_LABELS.items()}

SLOT_LABELS = {
    "top":  "Верх",
    "face": "Лицевая",
    "back": "Тыл",
    "base": "Основа",
}

MATERIAL_SLOT_LABELS = {
    "top":  "Верх",
    "face": "Лицевая",
    "base": "Основа / пол",
}

MATERIAL_SOURCE_LABELS = {
    "procedural": "Процедурный",
    "image":      "Файл",
    "flat":       "Цвет",
}
MATERIAL_SOURCE_KEYS_BY_LABEL = {label: key for key, label in MATERIAL_SOURCE_LABELS.items()}

MATERIAL_KIND_LABELS = {
    "stone_bricks":     "Каменные блоки / кирпичи",
    "cracked_earth":    "Растрескавшаяся сухая земля",
    "rough_stone":      "Грубый камень",
    "worn_metal":       "Потёртый металл",
    "wood_planks":      "Деревянные доски",
    "packed_dirt":      "Утрамбованная земля",
    "concrete":         "Бетон",
    "ice_frost":        "Лёд / иней",
    "ash_burnt_ground": "Пепел / выжженная земля",
    "snow":             "Снег",
    "sand":             "Песок",
    "moss":             "Мох",
    "gravel":           "Гравий / реголит",
    "rusty_metal":      "Ржавый металл",
    "concrete_floor":   "Бетонный пол со швами",
    "ribbed_steel":     "Рифлёная сталь",
}
MATERIAL_KIND_KEYS_BY_LABEL = {label: key for key, label in MATERIAL_KIND_LABELS.items()}

MATERIAL_DEFAULTS = {
    "top": {
        "source": "procedural", "kind": "rough_stone",
        "scale": 1.0, "contrast": 1.0, "crack_amount": 0.25, "wear": 0.2,
        "grain": 0.45, "edge_darkening": 0.25, "seed": 11,
        "color_a": "#5e5142", "color_b": "#8a7a62", "highlight": "#b9ad93",
    },
    "face": {
        "source": "procedural", "kind": "stone_bricks",
        "scale": 1.0, "contrast": 1.05, "crack_amount": 0.18, "wear": 0.28,
        "grain": 0.35, "edge_darkening": 0.45, "seed": 23,
        "color_a": "#3d3a34", "color_b": "#68665e", "highlight": "#9a9686",
    },
    "base": {
        "source": "procedural", "kind": "packed_dirt",
        "scale": 1.0, "contrast": 0.9, "crack_amount": 0.12, "wear": 0.2,
        "grain": 0.5, "edge_darkening": 0.1, "seed": 31,
        "color_a": "#7d4b1e", "color_b": "#b07232", "highlight": "#d19855",
    },
}


# ─── Tools ───────────────────────────────────────────────────────────────────

TOOL_BRUSH = "brush"
TOOL_ERASER = "eraser"
TOOL_FILL = "fill"
TOOL_LABELS = {
    TOOL_BRUSH:  "Кисть (B)",
    TOOL_ERASER: "Ластик (E)",
    TOOL_FILL:   "Заливка (F)",
}


# ─── Application ─────────────────────────────────────────────────────────────

class CliffForgeApp:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title(WINDOW_TITLE)

        # Persistent state
        self.state = self._load_state()

        # Runtime state
        self.render_queue: queue.Queue[tuple[str, object]] = queue.Queue()
        self.render_thread: threading.Thread | None = None
        self.pending_mode: str | None = None
        self.pending_export_dir: Path | None = None
        self.draft_after_id: str | None = None
        self.last_manifest: dict | None = None
        self.last_warnings: list[str] = []
        self.photo_refs: dict[str, ImageTk.PhotoImage] = {}
        self.suspend_events = False
        self.current_map = make_blob_map(MAP_DEFAULT_W, MAP_DEFAULT_H)
        self.map_history: deque[tuple[dict, dict]] = deque(maxlen=MAP_HISTORY_LIMIT)
        self.map_redo: deque[tuple[dict, dict]] = deque(maxlen=MAP_HISTORY_LIMIT)
        self.texture_paths = {"top": "", "face": "", "base": ""}
        self.preview_source_image: Image.Image | None = None
        self.preview_zoom = 1.0
        self.preview_offset_x = 0.0
        self.preview_offset_y = 0.0
        self.preview_drag_last: tuple[int, int] | None = None
        self.preview_render_size: tuple[int, int] | None = None
        self.atlas_source_image: Image.Image | None = None
        self.atlas_zoom = 1.0
        self.atlas_offset_x = 0.0
        self.atlas_offset_y = 0.0
        self.atlas_drag_last: tuple[int, int] | None = None
        self.atlas_render_size: tuple[int, int] | None = None
        self.tool = TOOL_BRUSH
        self.brush_size_var: tk.IntVar | None = None
        self.recent_colors: list[str] = list(self.state.get("recent_colors", []))
        self.recent_recipes: list[str] = list(self.state.get("recent_recipes", []))
        self.current_recipe_path: Path | None = None
        self.is_dirty = False

        # Set window geometry from state (or defaults)
        self.root.geometry(self.state.get("geometry", DEFAULT_GEOMETRY))
        self.root.minsize(*MIN_SIZE)
        self.root.configure(background=THEME["bg"])

        self._build_variables()
        self._setup_style()
        self._build_layout()
        self._bind_shortcuts()
        self._select_tool(TOOL_BRUSH, refresh=False)
        self._apply_preset(self.state.get("preset", "mountain"), schedule=False)
        self._refresh_variant_selector()
        self._refresh_recent_recipes()
        self._refresh_recent_colors()
        self._draw_map()
        self._set_status(STATUS_BOOT)
        self._update_title()

        self.root.protocol("WM_DELETE_WINDOW", self._on_close)
        self.root.after(120, self._poll_render_queue)
        self.request_render("full")

    # ─── State persistence ───────────────────────────────────────────────

    def _load_state(self) -> dict:
        try:
            return json.loads(STATE_FILE.read_text(encoding="utf-8"))
        except Exception:
            return {}

    def _save_state(self) -> None:
        try:
            self.state["geometry"] = self.root.geometry()
            self.state["preset"] = self._selected_preset_key()
            self.state["recent_colors"] = self.recent_colors[:RECENT_COLORS_LIMIT]
            self.state["recent_recipes"] = self.recent_recipes[:RECENT_RECIPES_LIMIT]
            STATE_FILE.write_text(json.dumps(self.state, indent=2, ensure_ascii=False), encoding="utf-8")
        except Exception:
            pass

    def _on_close(self) -> None:
        self._save_state()
        self.root.destroy()

    # ─── ttk style ───────────────────────────────────────────────────────

    def _setup_style(self) -> None:
        style = ttk.Style(self.root)
        if "clam" in style.theme_names():
            style.theme_use("clam")

        bg = THEME["bg"]
        panel = THEME["panel"]
        panel_alt = THEME["panel_alt"]
        fg = THEME["fg"]
        fg_dim = THEME["fg_dim"]
        accent = THEME["accent"]
        border = THEME["border"]
        input_bg = THEME["input"]

        style.configure(".", background=bg, foreground=fg, fieldbackground=input_bg, bordercolor=border)
        style.configure("TFrame", background=bg)
        style.configure("Panel.TFrame", background=panel)
        style.configure("Toolbar.TFrame", background=panel_alt)
        style.configure("Status.TFrame", background=panel_alt)

        style.configure("TLabel", background=bg, foreground=fg)
        style.configure("Panel.TLabel", background=panel, foreground=fg)
        style.configure("Toolbar.TLabel", background=panel_alt, foreground=fg)
        style.configure("Dim.TLabel", background=bg, foreground=fg_dim)
        style.configure("DimPanel.TLabel", background=panel, foreground=fg_dim)
        style.configure("DimStatus.TLabel", background=panel_alt, foreground=fg_dim)
        style.configure("Status.TLabel", background=panel_alt, foreground=fg)
        style.configure("Title.TLabel", background=bg, foreground=fg, font=("Segoe UI", 11, "bold"))
        style.configure("Section.TLabel", background=panel, foreground=accent, font=("Segoe UI", 9, "bold"))
        style.configure("Warn.TLabel", background=panel_alt, foreground=THEME["warn"])

        style.configure("TLabelframe", background=panel, foreground=fg, bordercolor=border, lightcolor=border, darkcolor=border)
        style.configure("TLabelframe.Label", background=panel, foreground=accent, font=("Segoe UI", 9, "bold"))

        style.configure("TButton", background=panel, foreground=fg, bordercolor=border, padding=(8, 4))
        style.map("TButton",
                  background=[("active", border), ("disabled", panel)],
                  foreground=[("disabled", fg_dim)])
        style.configure("Toolbar.TButton", background=panel_alt, foreground=fg, bordercolor=border, padding=(10, 5))
        style.map("Toolbar.TButton", background=[("active", border)])
        style.configure("Accent.TButton", background=accent, foreground="#1a1410", padding=(12, 5), font=("Segoe UI", 9, "bold"))
        style.map("Accent.TButton", background=[("active", "#d59c5f"), ("disabled", panel)])
        style.configure("Tool.TButton", background=panel, foreground=fg, padding=(8, 6))
        style.map("Tool.TButton", background=[("active", border)])
        style.configure("ToolActive.TButton", background=accent, foreground="#1a1410", padding=(8, 6), font=("Segoe UI", 9, "bold"))
        style.map("ToolActive.TButton", background=[("active", "#d59c5f")])
        style.configure("Mini.TButton", padding=(4, 2))
        style.map("Mini.TButton", background=[("active", border)])

        style.configure("TEntry", fieldbackground=input_bg, foreground=fg, bordercolor=border, insertcolor=fg)
        style.configure("TCombobox", fieldbackground=input_bg, foreground=fg, bordercolor=border, arrowcolor=fg)
        style.map("TCombobox", fieldbackground=[("readonly", input_bg)])
        self.root.option_add("*TCombobox*Listbox.background", panel_alt)
        self.root.option_add("*TCombobox*Listbox.foreground", fg)
        self.root.option_add("*TCombobox*Listbox.selectBackground", accent)
        self.root.option_add("*TCombobox*Listbox.selectForeground", "#1a1410")

        style.configure("TCheckbutton", background=panel, foreground=fg, indicatorcolor=input_bg)
        style.map("TCheckbutton", background=[("active", panel)])

        style.configure("TNotebook", background=bg, borderwidth=0)
        style.configure("TNotebook.Tab", background=panel_alt, foreground=fg_dim, padding=(14, 6), bordercolor=border)
        style.map("TNotebook.Tab",
                  background=[("selected", panel)],
                  foreground=[("selected", fg)])

        style.configure("TPanedwindow", background=bg)
        style.configure("Sash", background=border, sashthickness=4)

        style.configure("TProgressbar", troughcolor=border, background=accent, bordercolor=border)

        style.configure("TSeparator", background=border)

    # ─── Variables ───────────────────────────────────────────────────────

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
        self.texture_color_overlay_var = tk.BooleanVar(value=False)
        self.forced_variant_var = tk.StringVar(value=LABEL_AUTO_VARIANT)
        self.top_color_var = tk.StringVar(value="#705940")
        self.face_color_var = tk.StringVar(value="#3e2f25")
        self.back_color_var = tk.StringVar(value="#564436")
        self.base_color_var = tk.StringVar(value="#b88d58")
        self.stats_var = tk.StringVar(value=STATS_EMPTY)
        self.status_var = tk.StringVar(value=STATUS_IDLE)
        self.warnings_var = tk.StringVar(value="")
        self.brush_size_var = tk.IntVar(value=1)
        self.map_w_var = tk.IntVar(value=MAP_DEFAULT_W)
        self.map_h_var = tk.IntVar(value=MAP_DEFAULT_H)

        self.material_vars = {}
        for slot, defaults in MATERIAL_DEFAULTS.items():
            self.material_vars[slot] = {
                "source":         tk.StringVar(value=MATERIAL_SOURCE_LABELS[defaults["source"]]),
                "kind":           tk.StringVar(value=MATERIAL_KIND_LABELS[defaults["kind"]]),
                "scale":          tk.DoubleVar(value=defaults["scale"]),
                "contrast":       tk.DoubleVar(value=defaults["contrast"]),
                "crack_amount":   tk.DoubleVar(value=defaults["crack_amount"]),
                "wear":           tk.DoubleVar(value=defaults["wear"]),
                "grain":          tk.DoubleVar(value=defaults["grain"]),
                "edge_darkening": tk.DoubleVar(value=defaults["edge_darkening"]),
                "seed":           tk.IntVar(value=defaults["seed"]),
                "color_a":        tk.StringVar(value=defaults["color_a"]),
                "color_b":        tk.StringVar(value=defaults["color_b"]),
                "highlight":      tk.StringVar(value=defaults["highlight"]),
            }

    # ─── Layout ──────────────────────────────────────────────────────────

    def _build_layout(self) -> None:
        outer = ttk.Frame(self.root)
        outer.pack(fill="both", expand=True)
        outer.columnconfigure(0, weight=1)
        outer.rowconfigure(1, weight=1)

        toolbar = self._build_toolbar(outer)
        toolbar.grid(row=0, column=0, sticky="ew")

        paned = ttk.PanedWindow(outer, orient="horizontal")
        paned.grid(row=1, column=0, sticky="nsew", padx=4, pady=(4, 2))

        left_pane = ttk.Frame(paned, style="Panel.TFrame", padding=10)
        center_pane = ttk.Frame(paned, padding=4)
        right_pane = ttk.Frame(paned, style="Panel.TFrame", padding=4)
        paned.add(left_pane, weight=2)
        paned.add(center_pane, weight=5)
        paned.add(right_pane, weight=4)

        self._build_left_pane(left_pane)
        self._build_center_pane(center_pane)
        self._build_right_pane(right_pane)

        statusbar = self._build_statusbar(outer)
        statusbar.grid(row=2, column=0, sticky="ew")

    # ─── Top toolbar ─────────────────────────────────────────────────────

    def _build_toolbar(self, parent: ttk.Frame) -> ttk.Frame:
        bar = ttk.Frame(parent, style="Toolbar.TFrame", padding=(10, 8))

        # Render group
        ttk.Button(bar, text="▷  Превью", style="Toolbar.TButton", command=self.schedule_draft).pack(side="left")
        ttk.Button(bar, text="⊞  Полная сборка", style="Accent.TButton", command=self.schedule_full).pack(side="left", padx=(6, 0))
        self._toolbar_separator(bar)

        # Recipe group
        ttk.Button(bar, text="💾 Сохранить", style="Toolbar.TButton", command=self._save_recipe).pack(side="left")
        load_btn = ttk.Menubutton(bar, text="📂 Загрузить ▾", style="Toolbar.TButton")
        self.recent_recipes_menu = tk.Menu(load_btn, tearoff=0,
                                            background=THEME["panel_alt"], foreground=THEME["fg"],
                                            activebackground=THEME["accent"], activeforeground="#1a1410")
        load_btn.configure(menu=self.recent_recipes_menu)
        load_btn.pack(side="left", padx=(6, 0))
        ttk.Button(bar, text="⬇  Экспорт PNG", style="Toolbar.TButton", command=self._export_outputs).pack(side="left", padx=(6, 0))
        self._toolbar_separator(bar)

        # Preset + seed
        ttk.Label(bar, text="Пресет:", style="Toolbar.TLabel").pack(side="left")
        preset_combo = ttk.Combobox(bar, textvariable=self.preset_var,
                                     values=[PRESET_LABELS[k] for k in PRESETS.keys()],
                                     state="readonly", width=10)
        preset_combo.pack(side="left", padx=(4, 0))
        preset_combo.bind("<<ComboboxSelected>>", self._on_preset_changed)

        ttk.Label(bar, text="  Сид:", style="Toolbar.TLabel").pack(side="left")
        seed_entry = ttk.Entry(bar, textvariable=self.seed_var, width=12)
        seed_entry.pack(side="left", padx=(4, 0))
        seed_entry.bind("<Return>", lambda _e: self.schedule_full())
        ttk.Button(bar, text="🎲", width=3, style="Mini.TButton", command=self._randomize_seed).pack(side="left", padx=(4, 0))

        # Right-aligned: variant + preview mode
        ttk.Label(bar, text="Режим", style="Toolbar.TLabel").pack(side="right", padx=(6, 0))
        preview_combo = ttk.Combobox(bar, textvariable=self.preview_mode_var,
                                      values=[PREVIEW_MODE_LABELS[k] for k in PREVIEW_MODE_LABELS],
                                      state="readonly", width=11)
        preview_combo.pack(side="right", padx=(4, 0))
        preview_combo.bind("<<ComboboxSelected>>", lambda *_: self.schedule_draft())

        ttk.Label(bar, text="Вариант", style="Toolbar.TLabel").pack(side="right", padx=(10, 0))
        self.variant_combo = ttk.Combobox(bar, textvariable=self.forced_variant_var,
                                           values=[LABEL_AUTO_VARIANT], state="readonly", width=12)
        self.variant_combo.pack(side="right", padx=(4, 0))
        self.variant_combo.bind("<<ComboboxSelected>>", lambda *_: self.schedule_draft())

        return bar

    def _toolbar_separator(self, parent: ttk.Frame) -> None:
        sep = ttk.Separator(parent, orient="vertical")
        sep.pack(side="left", fill="y", padx=10)

    # ─── Left pane: Map editor ───────────────────────────────────────────

    def _build_left_pane(self, parent: ttk.Frame) -> None:
        ttk.Label(parent, text="Карта", style="Section.TLabel").pack(anchor="w", pady=(0, 6))

        # Tools row
        tools = ttk.Frame(parent, style="Panel.TFrame")
        tools.pack(fill="x", pady=(0, 6))
        self.tool_buttons: dict[str, ttk.Button] = {}
        for tool_id in (TOOL_BRUSH, TOOL_ERASER, TOOL_FILL):
            btn = ttk.Button(tools, text=TOOL_LABELS[tool_id], style="Tool.TButton",
                             command=lambda tid=tool_id: self._select_tool(tid))
            btn.pack(side="left", padx=(0, 4), fill="x", expand=True)
            self.tool_buttons[tool_id] = btn

        # Brush size
        brush_row = ttk.Frame(parent, style="Panel.TFrame")
        brush_row.pack(fill="x", pady=(0, 8))
        ttk.Label(brush_row, text="Кисть", style="Panel.TLabel", width=10).pack(side="left")
        for size in (1, 2, 3):
            btn = ttk.Button(brush_row, text=f"{size}", style="Mini.TButton", width=4,
                             command=lambda s=size: self.brush_size_var.set(s))
            btn.pack(side="left", padx=(0, 2))

        # Map canvas (centered, sized to current map)
        canvas_frame = ttk.Frame(parent, style="Panel.TFrame")
        canvas_frame.pack(fill="x", pady=(0, 8))
        self.map_canvas = tk.Canvas(
            canvas_frame, width=320, height=240,
            background=THEME["map_empty"],
            highlightthickness=1, highlightbackground=THEME["border"],
        )
        self.map_canvas.pack(anchor="center")
        self._bind_map_canvas()

        # Map size sliders
        size_frame = ttk.Frame(parent, style="Panel.TFrame")
        size_frame.pack(fill="x", pady=(0, 6))
        self._add_panel_scale(size_frame, "Ширина", self.map_w_var, MAP_W_RANGE[0], MAP_W_RANGE[1], 1,
                              integer=True, on_change=self._on_map_size_changed, debounce_full=False)
        self._add_panel_scale(size_frame, "Высота", self.map_h_var, MAP_H_RANGE[0], MAP_H_RANGE[1], 1,
                              integer=True, on_change=self._on_map_size_changed, debounce_full=False)

        # Map presets row
        presets_row = ttk.Frame(parent, style="Panel.TFrame")
        presets_row.pack(fill="x", pady=(2, 6))
        ttk.Button(presets_row, text="Пятно", style="Tool.TButton", command=self._make_blob_map).pack(side="left", padx=(0, 4), fill="x", expand=True)
        ttk.Button(presets_row, text="Комната", style="Tool.TButton", command=self._make_room_map).pack(side="left", padx=(0, 4), fill="x", expand=True)
        ttk.Button(presets_row, text="Пещера", style="Tool.TButton", command=self._make_cave_map).pack(side="left", padx=(0, 4), fill="x", expand=True)
        ttk.Button(presets_row, text="Очистить", style="Tool.TButton", command=self._clear_map).pack(side="left", fill="x", expand=True)

        # Undo / Redo
        history_row = ttk.Frame(parent, style="Panel.TFrame")
        history_row.pack(fill="x")
        ttk.Button(history_row, text="↶ Отменить (Ctrl+Z)", style="Tool.TButton", command=self._undo_map).pack(side="left", padx=(0, 4), fill="x", expand=True)
        ttk.Button(history_row, text="↷ Повторить", style="Tool.TButton", command=self._redo_map).pack(side="left", fill="x", expand=True)

        # Hint text
        hint = ttk.Label(parent,
                         text="ЛКМ — рисует, ПКМ — стирает.\nB / E / F — сменить инструмент.",
                         style="DimPanel.TLabel", justify="left")
        hint.pack(anchor="w", pady=(8, 0))

    # ─── Center pane: Preview / Atlas ────────────────────────────────────

    def _build_center_pane(self, parent: ttk.Frame) -> None:
        notebook = ttk.Notebook(parent)
        notebook.pack(fill="both", expand=True)

        # Preview tab
        preview_frame = ttk.Frame(notebook, padding=4)
        notebook.add(preview_frame, text="  Превью карты  ")
        preview_frame.columnconfigure(0, weight=1)
        preview_frame.rowconfigure(0, weight=1)
        self.preview_canvas = tk.Canvas(
            preview_frame, background=THEME["map_empty"],
            highlightthickness=1, highlightbackground=THEME["border"],
            takefocus=1,
        )
        self.preview_canvas.grid(row=0, column=0, sticky="nsew")
        self.preview_canvas.bind("<Configure>", lambda _e: self._render_preview_canvas())
        self.preview_canvas.bind("<Enter>", lambda _e: self.preview_canvas.focus_set())
        self.preview_canvas.bind("<MouseWheel>", self._on_preview_zoom)
        self.preview_canvas.bind("<Button-4>", self._on_preview_zoom)
        self.preview_canvas.bind("<Button-5>", self._on_preview_zoom)
        self.preview_canvas.bind("<ButtonPress-1>", self._start_preview_pan)
        self.preview_canvas.bind("<B1-Motion>", self._drag_preview_pan)
        self.preview_canvas.bind("<ButtonRelease-1>", self._end_preview_pan)
        self._render_preview_canvas()

        # Atlas tab
        atlas_frame = ttk.Frame(notebook, padding=4)
        notebook.add(atlas_frame, text="  Атлас  ")
        atlas_frame.columnconfigure(0, weight=1)
        atlas_frame.rowconfigure(0, weight=1)
        self.atlas_canvas = tk.Canvas(
            atlas_frame, background=THEME["map_empty"],
            highlightthickness=1, highlightbackground=THEME["border"],
            takefocus=1,
        )
        self.atlas_canvas.grid(row=0, column=0, sticky="nsew")
        self.atlas_canvas.bind("<Configure>", lambda _e: self._render_atlas_canvas())
        self.atlas_canvas.bind("<Enter>", lambda _e: self.atlas_canvas.focus_set())
        self.atlas_canvas.bind("<MouseWheel>", self._on_atlas_zoom)
        self.atlas_canvas.bind("<Button-4>", self._on_atlas_zoom)
        self.atlas_canvas.bind("<Button-5>", self._on_atlas_zoom)
        self.atlas_canvas.bind("<ButtonPress-1>", self._start_atlas_pan)
        self.atlas_canvas.bind("<B1-Motion>", self._drag_atlas_pan)
        self.atlas_canvas.bind("<ButtonRelease-1>", self._end_atlas_pan)
        self._render_atlas_canvas()

    # ─── Right pane: Inspector tabs ──────────────────────────────────────

    def _build_right_pane(self, parent: ttk.Frame) -> None:
        self.right_notebook = ttk.Notebook(parent)
        self.right_notebook.pack(fill="both", expand=True)

        geom_tab = self._make_scrolled_tab(self.right_notebook, "  Геометрия  ")
        self._build_geometry_tab(geom_tab)

        materials_tab = self._make_scrolled_tab(self.right_notebook, "  Материалы  ")
        self._build_materials_tab(materials_tab)

        colors_tab = self._make_scrolled_tab(self.right_notebook, "  Цвета и текстуры  ")
        self._build_colors_tab(colors_tab)

    def _make_scrolled_tab(self, notebook: ttk.Notebook, label: str) -> ttk.Frame:
        outer = ttk.Frame(notebook, style="Panel.TFrame")
        notebook.add(outer, text=label)
        canvas = tk.Canvas(outer, highlightthickness=0, background=THEME["panel"])
        scrollbar = ttk.Scrollbar(outer, orient="vertical", command=canvas.yview)
        canvas.configure(yscrollcommand=scrollbar.set)
        canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        inner = ttk.Frame(canvas, style="Panel.TFrame", padding=(12, 10))
        window_id = canvas.create_window((0, 0), window=inner, anchor="nw")

        def sync_region(_e: tk.Event) -> None:
            canvas.configure(scrollregion=canvas.bbox("all"))

        def sync_width(event: tk.Event) -> None:
            canvas.itemconfigure(window_id, width=event.width)

        inner.bind("<Configure>", sync_region)
        canvas.bind("<Configure>", sync_width)
        canvas.bind("<Enter>", lambda _e: canvas.bind_all("<MouseWheel>", lambda ev: canvas.yview_scroll(int(-ev.delta / 60), "units")))
        canvas.bind("<Leave>", lambda _e: canvas.unbind_all("<MouseWheel>"))
        return inner

    def _build_geometry_tab(self, parent: ttk.Frame) -> None:
        group = ttk.LabelFrame(parent, text="Размер тайла", padding=10)
        group.pack(fill="x", pady=(0, 10))
        self._add_panel_scale(group, "Размер тайла", self.tile_size_var, 32, 96, 16, integer=True)
        self._add_panel_scale(group, "Кол-во вариантов", self.variants_var, 1, 8, 1, integer=True,
                              on_change=self._on_variant_count_changed, debounce_full=False)
        self._add_panel_scale(group, "Масштаб текстуры", self.texture_scale_var, 0.25, 4.0, 0.05)

        group = ttk.LabelFrame(parent, text="Высоты", padding=10)
        group.pack(fill="x", pady=(0, 10))
        self._add_panel_scale(group, "Южная высота", self.south_height_var, 4, 32, 1, integer=True)
        self._add_panel_scale(group, "Северная высота", self.north_height_var, 2, 24, 1, integer=True)
        self._add_panel_scale(group, "Боковая высота", self.side_height_var, 2, 24, 1, integer=True)

        group = ttk.LabelFrame(parent, text="Кромка", padding=10)
        group.pack(fill="x", pady=(0, 10))
        self._add_panel_scale(group, "Шероховатость", self.roughness_var, 0, 100, 1)
        self._add_panel_scale(group, "Сила фасада", self.face_power_var, 0.4, 2.8, 0.05)
        self._add_panel_scale(group, "Задний спад", self.back_drop_var, 0.1, 0.8, 0.01)
        self._add_panel_scale(group, "Скос гребня", self.crown_bevel_var, 0, 12, 1, integer=True)

    def _build_materials_tab(self, parent: ttk.Frame) -> None:
        toolbar = ttk.Frame(parent, style="Panel.TFrame")
        toolbar.pack(fill="x", pady=(0, 8))
        ttk.Label(toolbar, text="Слои стека: верх → лицо → основа.", style="DimPanel.TLabel").pack(side="left")
        ttk.Button(toolbar, text="↺ Сброс к пресету", style="Mini.TButton",
                   command=self._reset_materials_to_preset).pack(side="right")
        for slot in ("top", "face", "base"):
            self._build_material_slot(parent, slot)

    def _build_material_slot(self, parent: ttk.Frame, slot: str) -> None:
        group = ttk.LabelFrame(parent, text=MATERIAL_SLOT_LABELS[slot], padding=10)
        group.pack(fill="x", pady=(0, 10))
        group.columnconfigure(0, weight=1)
        group.columnconfigure(1, weight=1)

        left = ttk.Frame(group, style="Panel.TFrame")
        left.grid(row=0, column=0, sticky="nsew", padx=(0, 12))
        right = ttk.Frame(group, style="Panel.TFrame")
        right.grid(row=0, column=1, sticky="nsew")

        vars_for_slot = self.material_vars[slot]
        copy_row = ttk.Frame(group, style="Panel.TFrame")
        copy_row.grid(row=1, column=0, columnspan=2, sticky="ew", pady=(8, 0))
        ttk.Label(copy_row, text="Скопировать в:", style="DimPanel.TLabel").pack(side="left")
        for target in ("top", "face", "base"):
            if target == slot:
                continue
            ttk.Button(copy_row, text=MATERIAL_SLOT_LABELS[target], style="Mini.TButton",
                       command=lambda src=slot, dst=target: self._copy_material(src, dst)).pack(side="left", padx=(6, 0))

        self._add_panel_combo(left, "Источник", vars_for_slot["source"],
                              [MATERIAL_SOURCE_LABELS[k] for k in MATERIAL_SOURCE_LABELS],
                              lambda *_: self.schedule_full())
        self._add_panel_combo(left, "Тип", vars_for_slot["kind"],
                              [MATERIAL_KIND_LABELS[k] for k in MATERIAL_KIND_LABELS],
                              lambda *_: self.schedule_full())
        self._add_panel_seed(left, "Сид материала", vars_for_slot["seed"])
        self._add_panel_color(left, "Цвет A", vars_for_slot["color_a"])
        self._add_panel_color(left, "Цвет B", vars_for_slot["color_b"])
        self._add_panel_color(left, "Блик", vars_for_slot["highlight"])

        self._add_panel_scale(right, "Масштаб", vars_for_slot["scale"], 0.2, 8.0, 0.05)
        self._add_panel_scale(right, "Контраст", vars_for_slot["contrast"], 0.0, 2.0, 0.05)
        self._add_panel_scale(right, "Трещины", vars_for_slot["crack_amount"], 0.0, 1.0, 0.01)
        self._add_panel_scale(right, "Износ", vars_for_slot["wear"], 0.0, 1.0, 0.01)
        self._add_panel_scale(right, "Зерно", vars_for_slot["grain"], 0.0, 1.0, 0.01)
        self._add_panel_scale(right, "Затемнение краёв", vars_for_slot["edge_darkening"], 0.0, 1.0, 0.01)

    def _build_colors_tab(self, parent: ttk.Frame) -> None:
        # Recent palette
        palette_frame = ttk.LabelFrame(parent, text="Недавние цвета", padding=10)
        palette_frame.pack(fill="x", pady=(0, 10))
        self.recent_colors_strip = ttk.Frame(palette_frame, style="Panel.TFrame")
        self.recent_colors_strip.pack(fill="x")
        ttk.Label(palette_frame, text="Кликни по свотчу — он скопируется в последнее изменённое поле.",
                  style="DimPanel.TLabel").pack(anchor="w", pady=(4, 0))
        self.last_color_var: tk.StringVar | None = None

        # Zone colors
        zones = ttk.LabelFrame(parent, text="Цвета зон", padding=10)
        zones.pack(fill="x", pady=(0, 10))
        self._add_panel_color(zones, SLOT_LABELS["top"], self.top_color_var)
        self._add_panel_color(zones, SLOT_LABELS["face"], self.face_color_var)
        self._add_panel_color(zones, SLOT_LABELS["back"], self.back_color_var)
        self._add_panel_color(zones, SLOT_LABELS["base"], self.base_color_var)

        # Texture loaders
        textures = ttk.LabelFrame(parent, text="Текстуры из файлов", padding=10)
        textures.pack(fill="x", pady=(0, 10))
        ttk.Checkbutton(textures, text=TEXT_TEXTURE_COLOR_OVERLAY,
                        variable=self.texture_color_overlay_var,
                        command=self.schedule_full).pack(fill="x", pady=(0, 8))
        self.texture_labels: dict[str, ttk.Label] = {}
        for slot in ("top", "face", "base"):
            row = ttk.Frame(textures, style="Panel.TFrame")
            row.pack(fill="x", pady=3)
            ttk.Label(row, text=SLOT_LABELS[slot], style="Panel.TLabel", width=10).pack(side="left")
            label = ttk.Label(row, text=TEXT_PROCEDURAL, style="DimPanel.TLabel", width=22, anchor="w")
            label.pack(side="left", padx=(4, 6), fill="x", expand=True)
            ttk.Button(row, text="Файл…", style="Mini.TButton",
                       command=lambda s=slot: self._load_texture(s)).pack(side="left")
            ttk.Button(row, text="✕", style="Mini.TButton", width=3,
                       command=lambda s=slot: self._clear_texture(s)).pack(side="left", padx=(4, 0))
            self.texture_labels[slot] = label

    # ─── Status bar ──────────────────────────────────────────────────────

    def _build_statusbar(self, parent: ttk.Frame) -> ttk.Frame:
        bar = ttk.Frame(parent, style="Status.TFrame", padding=(10, 6))
        bar.columnconfigure(2, weight=1)

        self.progress = ttk.Progressbar(bar, mode="indeterminate", length=140)
        self.progress.grid(row=0, column=0, sticky="w")

        ttk.Label(bar, textvariable=self.status_var, style="Status.TLabel").grid(row=0, column=1, sticky="w", padx=(10, 0))

        ttk.Label(bar, textvariable=self.stats_var, style="DimStatus.TLabel").grid(row=0, column=2, sticky="e")

        self.warnings_label = ttk.Label(bar, textvariable=self.warnings_var, style="Warn.TLabel", cursor="hand2")
        self.warnings_label.grid(row=0, column=3, sticky="e", padx=(12, 0))
        self.warnings_label.bind("<Button-1>", lambda _e: self._show_warnings())

        return bar

    # ─── Helpers: scales / combos / colors ───────────────────────────────

    def _add_panel_scale(self, parent: ttk.Widget, label: str, variable: tk.Variable,
                         start: float, end: float, resolution: float, *,
                         integer: bool = False,
                         on_change=None,
                         debounce_full: bool = True) -> None:
        frame = ttk.Frame(parent, style="Panel.TFrame")
        frame.pack(fill="x", pady=(2, 6))
        head = ttk.Frame(frame, style="Panel.TFrame")
        head.pack(fill="x")
        ttk.Label(head, text=label, style="Panel.TLabel").pack(side="left")
        value_label = ttk.Label(head, text=self._format_var(variable), style="DimPanel.TLabel")
        value_label.pack(side="right")

        scale = tk.Scale(
            frame, from_=start, to=end, orient="horizontal",
            resolution=resolution, variable=variable, showvalue=False,
            background=THEME["panel"], foreground=THEME["fg"],
            troughcolor=THEME["input"], highlightthickness=0,
            activebackground=THEME["accent"],
            command=lambda _v, var=variable, lbl=value_label: self._on_scale_change(var, lbl),
        )
        scale.pack(fill="x")
        if debounce_full:
            scale.bind("<ButtonRelease-1>", lambda _e: self.schedule_full())
        if on_change:
            scale.bind("<ButtonRelease-1>", lambda _e: on_change(), add="+")

    def _add_panel_combo(self, parent: ttk.Widget, label: str, variable: tk.StringVar,
                         values: list[str], callback) -> None:
        row = ttk.Frame(parent, style="Panel.TFrame")
        row.pack(fill="x", pady=(2, 6))
        ttk.Label(row, text=label, style="Panel.TLabel", width=15).pack(side="left")
        combo = ttk.Combobox(row, textvariable=variable, values=values, state="readonly")
        combo.pack(side="left", fill="x", expand=True)
        combo.bind("<<ComboboxSelected>>", callback)

    def _add_panel_color(self, parent: ttk.Widget, label: str, variable: tk.StringVar) -> None:
        row = ttk.Frame(parent, style="Panel.TFrame")
        row.pack(fill="x", pady=3)
        ttk.Label(row, text=label, style="Panel.TLabel", width=10).pack(side="left")
        entry = ttk.Entry(row, textvariable=variable, width=10)
        entry.pack(side="left", padx=(4, 6))
        entry.bind("<Return>", lambda _e: self.schedule_full())
        entry.bind("<FocusIn>", lambda _e, v=variable: self._on_color_field_focus(v))
        swatch = tk.Button(
            row, width=3, relief="flat",
            background=variable.get(),
            activebackground=variable.get(),
            command=lambda var=variable: self._pick_color(var),
        )
        swatch.pack(side="left")
        variable.trace_add("write", lambda *_a, btn=swatch, var=variable: self._sync_color_button(btn, var))

    def _add_panel_seed(self, parent: ttk.Widget, label: str, variable: tk.IntVar) -> None:
        row = ttk.Frame(parent, style="Panel.TFrame")
        row.pack(fill="x", pady=(2, 6))
        ttk.Label(row, text=label, style="Panel.TLabel", width=15).pack(side="left")
        entry = ttk.Entry(row, textvariable=variable, width=12)
        entry.pack(side="left", fill="x", expand=True)
        entry.bind("<Return>", lambda _e: self.schedule_full())
        ttk.Button(row, text="🎲", width=3, style="Mini.TButton",
                   command=lambda v=variable: v.set(random.randint(1, 99_999))).pack(side="left", padx=(4, 0))

    def _on_color_field_focus(self, variable: tk.StringVar) -> None:
        self.last_color_var = variable

    def _sync_color_button(self, button: tk.Button, variable: tk.StringVar) -> None:
        try:
            button.configure(background=variable.get(), activebackground=variable.get())
        except tk.TclError:
            pass
        if not self.suspend_events:
            self.schedule_draft()

    def _pick_color(self, variable: tk.StringVar) -> None:
        self.last_color_var = variable
        _, hex_value = colorchooser.askcolor(color=variable.get(), parent=self.root)
        if hex_value:
            variable.set(hex_value)
            self._add_recent_color(hex_value)
            self.schedule_full()

    def _add_recent_color(self, hex_value: str) -> None:
        if not hex_value:
            return
        if hex_value in self.recent_colors:
            self.recent_colors.remove(hex_value)
        self.recent_colors.insert(0, hex_value)
        del self.recent_colors[RECENT_COLORS_LIMIT:]
        self._refresh_recent_colors()

    def _refresh_recent_colors(self) -> None:
        if not hasattr(self, "recent_colors_strip"):
            return
        for child in self.recent_colors_strip.winfo_children():
            child.destroy()
        if not self.recent_colors:
            ttk.Label(self.recent_colors_strip, text="—", style="DimPanel.TLabel").pack(side="left")
            return
        for hex_value in self.recent_colors:
            swatch = tk.Button(
                self.recent_colors_strip, width=2, height=1, relief="flat",
                background=hex_value, activebackground=hex_value,
                command=lambda v=hex_value: self._apply_recent_color(v),
            )
            swatch.pack(side="left", padx=(0, 3))

    def _apply_recent_color(self, hex_value: str) -> None:
        if self.last_color_var is None:
            return
        self.last_color_var.set(hex_value)
        self._add_recent_color(hex_value)
        self.schedule_full()

    def _format_var(self, variable: tk.Variable) -> str:
        value = variable.get()
        if isinstance(value, float):
            return f"{value:.2f}"
        return str(value)

    def _on_scale_change(self, variable: tk.Variable, label: ttk.Label) -> None:
        label.configure(text=self._format_var(variable))
        if self.suspend_events:
            return
        self._mark_dirty()
        self.schedule_draft()

    # ─── Map editor ──────────────────────────────────────────────────────

    def _bind_map_canvas(self) -> None:
        self.map_canvas.bind("<Button-1>", self._on_map_lmb_press)
        self.map_canvas.bind("<B1-Motion>", self._on_map_lmb_motion)
        self.map_canvas.bind("<Button-3>", self._on_map_rmb_press)
        self.map_canvas.bind("<B3-Motion>", self._on_map_rmb_motion)
        self.map_canvas.bind("<ButtonRelease-1>", self._on_map_release)
        self.map_canvas.bind("<ButtonRelease-3>", self._on_map_release)

    def _select_tool(self, tool_id: str, refresh: bool = True) -> None:
        self.tool = tool_id
        if refresh and hasattr(self, "tool_buttons"):
            for tid, btn in self.tool_buttons.items():
                btn.configure(style="ToolActive.TButton" if tid == tool_id else "Tool.TButton")

    def _cell_size(self) -> int:
        canvas_w = int(self.map_canvas["width"])
        canvas_h = int(self.map_canvas["height"])
        cs_w = canvas_w // self.current_map["width"]
        cs_h = canvas_h // self.current_map["height"]
        return max(6, min(cs_w, cs_h))

    def _coord_to_cell(self, event: tk.Event) -> tuple[int, int] | None:
        cs = self._cell_size()
        x = event.x // cs
        y = event.y // cs
        if 0 <= x < self.current_map["width"] and 0 <= y < self.current_map["height"]:
            return x, y
        return None

    def _on_map_lmb_press(self, event: tk.Event) -> None:
        self._push_map_history()
        if self.tool == TOOL_FILL:
            cell = self._coord_to_cell(event)
            if cell:
                self._flood_fill(cell[0], cell[1], target=1)
            self._draw_map()
            self.schedule_draft()
            return
        self._paint_at(event, value=0 if self.tool == TOOL_ERASER else 1)

    def _on_map_lmb_motion(self, event: tk.Event) -> None:
        if self.tool == TOOL_FILL:
            return
        self._paint_at(event, value=0 if self.tool == TOOL_ERASER else 1)

    def _on_map_rmb_press(self, event: tk.Event) -> None:
        self._push_map_history()
        if self.tool == TOOL_FILL:
            cell = self._coord_to_cell(event)
            if cell:
                self._flood_fill(cell[0], cell[1], target=0)
            self._draw_map()
            self.schedule_draft()
            return
        self._paint_at(event, value=0)

    def _on_map_rmb_motion(self, event: tk.Event) -> None:
        if self.tool == TOOL_FILL:
            return
        self._paint_at(event, value=0)

    def _on_map_release(self, _event: tk.Event) -> None:
        self.schedule_full()

    def _paint_at(self, event: tk.Event, *, value: int) -> None:
        cell = self._coord_to_cell(event)
        if not cell:
            return
        cx, cy = cell
        radius = max(0, self.brush_size_var.get() - 1)
        w = self.current_map["width"]
        h = self.current_map["height"]
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                x = cx + dx
                y = cy + dy
                if 0 <= x < w and 0 <= y < h:
                    self.current_map["cells"][y * w + x] = value
        self._mark_dirty()
        self._draw_map()
        self.schedule_draft()

    def _flood_fill(self, x: int, y: int, *, target: int) -> None:
        w = self.current_map["width"]
        h = self.current_map["height"]
        cells = self.current_map["cells"]
        start = cells[y * w + x]
        if start == target:
            return
        stack = [(x, y)]
        while stack:
            sx, sy = stack.pop()
            if not (0 <= sx < w and 0 <= sy < h):
                continue
            if cells[sy * w + sx] != start:
                continue
            cells[sy * w + sx] = target
            stack.extend([(sx + 1, sy), (sx - 1, sy), (sx, sy + 1), (sx, sy - 1)])
        self._mark_dirty()

    def _push_map_history(self) -> None:
        snapshot = ({"width": self.current_map["width"], "height": self.current_map["height"]},
                    list(self.current_map["cells"]))
        self.map_history.append((snapshot[0], {"cells": snapshot[1]}))
        self.map_redo.clear()

    def _restore_map(self, snapshot: tuple[dict, dict]) -> None:
        size, payload = snapshot
        self.current_map = {
            "width": size["width"],
            "height": size["height"],
            "cells": list(payload["cells"]),
        }
        self.map_w_var.set(size["width"])
        self.map_h_var.set(size["height"])
        self._draw_map()
        self.schedule_full()

    def _undo_map(self) -> None:
        if not self.map_history:
            return
        current = ({"width": self.current_map["width"], "height": self.current_map["height"]},
                   {"cells": list(self.current_map["cells"])})
        self.map_redo.append(current)
        self._restore_map(self.map_history.pop())

    def _redo_map(self) -> None:
        if not self.map_redo:
            return
        current = ({"width": self.current_map["width"], "height": self.current_map["height"]},
                   {"cells": list(self.current_map["cells"])})
        self.map_history.append(current)
        self._restore_map(self.map_redo.pop())

    def _on_map_size_changed(self) -> None:
        new_w = int(self.map_w_var.get())
        new_h = int(self.map_h_var.get())
        if new_w == self.current_map["width"] and new_h == self.current_map["height"]:
            return
        self._push_map_history()
        old_w = self.current_map["width"]
        old_h = self.current_map["height"]
        new_cells = [0] * (new_w * new_h)
        for y in range(min(old_h, new_h)):
            for x in range(min(old_w, new_w)):
                new_cells[y * new_w + x] = self.current_map["cells"][y * old_w + x]
        self.current_map = {"width": new_w, "height": new_h, "cells": new_cells}
        self._draw_map()
        self.schedule_full()

    def _draw_map(self) -> None:
        self.map_canvas.delete("all")
        cs = self._cell_size()
        w = self.current_map["width"]
        h = self.current_map["height"]
        new_canvas_w = max(220, w * cs)
        new_canvas_h = max(180, h * cs)
        if int(self.map_canvas["width"]) != new_canvas_w or int(self.map_canvas["height"]) != new_canvas_h:
            self.map_canvas.configure(width=new_canvas_w, height=new_canvas_h)
        for y in range(h):
            for x in range(w):
                index = y * w + x
                filled = self.current_map["cells"][index] > 0
                left = x * cs
                top = y * cs
                self.map_canvas.create_rectangle(
                    left, top, left + cs, top + cs,
                    fill=THEME["map_fill"] if filled else THEME["map_empty"],
                    outline=THEME["map_grid"],
                )

    # ─── Map presets ─────────────────────────────────────────────────────

    def _make_blob_map(self) -> None:
        self._push_map_history()
        self.current_map = make_blob_map(self.current_map["width"], self.current_map["height"])
        self.map_w_var.set(self.current_map["width"])
        self.map_h_var.set(self.current_map["height"])
        self._mark_dirty()
        self._draw_map()
        self.schedule_full()

    def _make_room_map(self) -> None:
        self._push_map_history()
        self.current_map = make_room_map(self.current_map["width"], self.current_map["height"])
        self.map_w_var.set(self.current_map["width"])
        self.map_h_var.set(self.current_map["height"])
        self._mark_dirty()
        self._draw_map()
        self.schedule_full()

    def _make_cave_map(self) -> None:
        self._push_map_history()
        self.current_map = make_cave_map(int(self.seed_var.get()),
                                          self.current_map["width"], self.current_map["height"])
        self.map_w_var.set(self.current_map["width"])
        self.map_h_var.set(self.current_map["height"])
        self._mark_dirty()
        self._draw_map()
        self.schedule_full()

    def _clear_map(self) -> None:
        self._push_map_history()
        w = self.current_map["width"]
        h = self.current_map["height"]
        self.current_map = {"width": w, "height": h, "cells": [0] * (w * h)}
        self._mark_dirty()
        self._draw_map()
        self.schedule_full()

    # ─── Preset / variant ────────────────────────────────────────────────

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
            self._mark_dirty()
            self.schedule_full()

    def _on_variant_count_changed(self) -> None:
        self._refresh_variant_selector()
        self.schedule_full()

    def _refresh_variant_selector(self) -> None:
        total = max(1, int(self.variants_var.get()))
        values = [LABEL_AUTO_VARIANT] + [f"{LABEL_VARIANT_PREFIX}{i + 1}" for i in range(total)]
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

    def _reset_materials_to_preset(self) -> None:
        self.suspend_events = True
        try:
            for slot, defaults in MATERIAL_DEFAULTS.items():
                vars_for_slot = self.material_vars[slot]
                vars_for_slot["source"].set(MATERIAL_SOURCE_LABELS[defaults["source"]])
                vars_for_slot["kind"].set(MATERIAL_KIND_LABELS[defaults["kind"]])
                for key in ("scale", "contrast", "crack_amount", "wear", "grain", "edge_darkening", "seed"):
                    vars_for_slot[key].set(defaults[key])
                vars_for_slot["color_a"].set(defaults["color_a"])
                vars_for_slot["color_b"].set(defaults["color_b"])
                vars_for_slot["highlight"].set(defaults["highlight"])
        finally:
            self.suspend_events = False
        self.schedule_full()

    def _copy_material(self, src: str, dst: str) -> None:
        self.suspend_events = True
        try:
            src_vars = self.material_vars[src]
            dst_vars = self.material_vars[dst]
            for key in dst_vars:
                dst_vars[key].set(src_vars[key].get())
        finally:
            self.suspend_events = False
        self.schedule_full()

    # ─── Texture loaders ─────────────────────────────────────────────────

    def _load_texture(self, slot: str) -> None:
        file_path = filedialog.askopenfilename(
            title=f"Загрузить текстуру: {SLOT_LABELS[slot]}",
            filetypes=[("Изображения", "*.png;*.jpg;*.jpeg;*.bmp;*.webp"), ("Все файлы", "*.*")],
        )
        if not file_path:
            return
        self.texture_paths[slot] = file_path
        self.material_vars[slot]["source"].set(MATERIAL_SOURCE_LABELS["image"])
        self.texture_labels[slot].configure(text=Path(file_path).name)
        self.schedule_full()

    def _clear_texture(self, slot: str) -> None:
        self.texture_paths[slot] = ""
        self.material_vars[slot]["source"].set(MATERIAL_SOURCE_LABELS["procedural"])
        self.texture_labels[slot].configure(text=TEXT_PROCEDURAL)
        self.schedule_full()

    # ─── Request building ────────────────────────────────────────────────

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
            "texture_color_overlay": bool(self.texture_color_overlay_var.get()),
            "preview_mode": self._selected_preview_mode_key(),
            "textures": {
                "top": self.texture_paths["top"] or None,
                "face": self.texture_paths["face"] or None,
                "base": self.texture_paths["base"] or None,
            },
            "materials": self._build_materials_payload(),
            "colors": {
                "top": self.top_color_var.get(),
                "face": self.face_color_var.get(),
                "back": self.back_color_var.get(),
                "base": self.base_color_var.get(),
            },
            "map": self.current_map,
        }

    def _build_materials_payload(self) -> dict:
        payload = {}
        for slot, vars_for_slot in self.material_vars.items():
            payload[slot] = {
                "source":         MATERIAL_SOURCE_KEYS_BY_LABEL.get(vars_for_slot["source"].get(), "procedural"),
                "kind":           MATERIAL_KIND_KEYS_BY_LABEL.get(vars_for_slot["kind"].get(), "rough_stone"),
                "scale":          float(vars_for_slot["scale"].get()),
                "contrast":       float(vars_for_slot["contrast"].get()),
                "crack_amount":   float(vars_for_slot["crack_amount"].get()),
                "wear":           float(vars_for_slot["wear"].get()),
                "grain":          float(vars_for_slot["grain"].get()),
                "edge_darkening": float(vars_for_slot["edge_darkening"].get()),
                "seed":           int(vars_for_slot["seed"].get()),
                "color_a":        vars_for_slot["color_a"].get(),
                "color_b":        vars_for_slot["color_b"].get(),
                "highlight":      vars_for_slot["highlight"].get(),
            }
        return payload

    # ─── Render scheduling ───────────────────────────────────────────────

    def schedule_draft(self) -> None:
        self._mark_dirty()
        if self.draft_after_id:
            self.root.after_cancel(self.draft_after_id)
        self.draft_after_id = self.root.after(180, lambda: self.request_render("draft"))

    def schedule_full(self) -> None:
        self._mark_dirty()
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
        self._set_status(f"Идёт {mode_label} рендер…")
        self._set_progress_active(True)

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
        self.last_warnings = list(manifest.get("warnings") or [])
        self._update_warnings_label()
        self._update_images(manifest)
        self.stats_var.set(
            f"Сборка: {manifest.get('build_ms', '?')} мс  ·  "
            f"Сигнатур: {manifest.get('signature_count', '?')}  ·  "
            f"Тайлы: {manifest.get('total_tiles', '?')}"
        )
        mode_value = manifest.get("mode", "render")
        mode_label = {"draft": "Черновой", "full": "Полный"}.get(mode_value, "Рендер")
        self._set_status(f"{mode_label} рендер завершён.")
        self._set_progress_active(False)

        if self.pending_export_dir and manifest.get("mode") == "full":
            export_dir = self.pending_export_dir
            self.pending_export_dir = None
            self._copy_outputs_to(export_dir)

        if self.pending_mode:
            next_mode = self.pending_mode
            self.pending_mode = None
            self.request_render(next_mode)

    def _handle_error(self, error: Exception) -> None:
        self._set_progress_active(False)
        self._set_status(f"Ошибка: {error}")
        messagebox.showerror(WINDOW_TITLE, str(error))
        if self.pending_mode:
            next_mode = self.pending_mode
            self.pending_mode = None
            self.request_render(next_mode)

    def _set_progress_active(self, active: bool) -> None:
        if active:
            try:
                self.progress.start(40)
            except tk.TclError:
                pass
        else:
            try:
                self.progress.stop()
            except tk.TclError:
                pass

    def _update_warnings_label(self) -> None:
        if not self.last_warnings:
            self.warnings_var.set("")
        else:
            count = len(self.last_warnings)
            label = "предупреждение" if count == 1 else "предупреждений"
            self.warnings_var.set(f"⚠ {count} {label} (нажми, чтобы посмотреть)")

    def _show_warnings(self) -> None:
        if not self.last_warnings:
            return
        text = "\n\n".join(self.last_warnings)
        messagebox.showwarning(WINDOW_TITLE + " — Предупреждения", text)

    # ─── Image display ───────────────────────────────────────────────────

    def _update_images(self, manifest: dict) -> None:
        files = manifest.get("files", {})
        preview_path = Path(files.get("preview_png", ""))
        if preview_path.exists():
            self._set_preview_image(preview_path)

        mode = self._selected_preview_mode_key()
        atlas_value = {
            "composite": files.get("atlas_albedo_png"),
            "albedo":    files.get("atlas_albedo_png"),
            "mask":      files.get("atlas_mask_png"),
            "height":    files.get("atlas_height_png"),
            "normal":    files.get("atlas_normal_png"),
        }.get(mode)

        if atlas_value:
            atlas_path = Path(atlas_value)
            if atlas_path.exists():
                self._set_atlas_image(atlas_path)

    def _set_preview_image(self, path: Path) -> None:
        with Image.open(path) as image:
            self.preview_source_image = image.copy()
        self.preview_render_size = None
        self.photo_refs.pop("preview", None)
        self._render_preview_canvas()

    def _set_atlas_image(self, path: Path) -> None:
        with Image.open(path) as image:
            self.atlas_source_image = image.copy()
        self.atlas_render_size = None
        self.photo_refs.pop("atlas", None)
        self._render_atlas_canvas()

    def _render_zoomable(self, canvas: tk.Canvas, source: Image.Image | None,
                         zoom: float, offset_x: float, offset_y: float,
                         render_size_attr: str, photo_key: str,
                         empty_text: str) -> tuple[float, float]:
        width = max(1, canvas.winfo_width())
        height = max(1, canvas.winfo_height())
        canvas.delete("all")

        if source is None:
            canvas.create_text(width // 2, height // 2,
                                text=empty_text + "\n" + TEXT_PREVIEW_HINT,
                                fill=THEME["fg_dim"], font=("Segoe UI", 12), justify="center")
            return offset_x, offset_y

        fit_scale = min(width / source.width, height / source.height)
        fit_scale = max(fit_scale, 0.01)
        scale = fit_scale * zoom
        target_size = (max(1, int(round(source.width * scale))),
                       max(1, int(round(source.height * scale))))
        max_offset_x = max(0.0, (target_size[0] - width) / 2.0)
        max_offset_y = max(0.0, (target_size[1] - height) / 2.0)
        offset_x = min(max(offset_x, -max_offset_x), max_offset_x)
        offset_y = min(max(offset_y, -max_offset_y), max_offset_y)

        previous = getattr(self, render_size_attr, None)
        if previous != target_size or photo_key not in self.photo_refs:
            render_image = source.resize(target_size, Image.Resampling.NEAREST)
            self.photo_refs[photo_key] = ImageTk.PhotoImage(render_image)
            setattr(self, render_size_attr, target_size)

        photo = self.photo_refs[photo_key]
        canvas.create_image(int(round(width / 2 + offset_x)),
                            int(round(height / 2 + offset_y)),
                            image=photo, anchor="center")
        canvas.create_text(12, 10,
                            text=f"Зум: {zoom:.2f}×",
                            fill=THEME["fg"], font=("Segoe UI", 9, "bold"), anchor="nw")
        return offset_x, offset_y

    def _render_preview_canvas(self) -> None:
        if not hasattr(self, "preview_canvas"):
            return
        self.preview_offset_x, self.preview_offset_y = self._render_zoomable(
            self.preview_canvas, self.preview_source_image,
            self.preview_zoom, self.preview_offset_x, self.preview_offset_y,
            "preview_render_size", "preview", TEXT_PREVIEW_EMPTY,
        )

    def _render_atlas_canvas(self) -> None:
        if not hasattr(self, "atlas_canvas"):
            return
        self.atlas_offset_x, self.atlas_offset_y = self._render_zoomable(
            self.atlas_canvas, self.atlas_source_image,
            self.atlas_zoom, self.atlas_offset_x, self.atlas_offset_y,
            "atlas_render_size", "atlas", "Атлас ещё не собран",
        )

    def _zoom_event(self, event: tk.Event, current_zoom: float) -> float:
        delta = getattr(event, "delta", 0)
        if delta == 0 and getattr(event, "num", None) == 4:
            delta = 120
        elif delta == 0 and getattr(event, "num", None) == 5:
            delta = -120
        if delta == 0:
            return current_zoom
        step = 1.15 if delta > 0 else 1.0 / 1.15
        return min(8.0, max(0.5, current_zoom * step))

    def _on_preview_zoom(self, event: tk.Event) -> str:
        if self.preview_source_image is None:
            return "break"
        next_zoom = self._zoom_event(event, self.preview_zoom)
        if abs(next_zoom - self.preview_zoom) > 1e-6:
            self.preview_zoom = next_zoom
            self._render_preview_canvas()
        return "break"

    def _on_atlas_zoom(self, event: tk.Event) -> str:
        if self.atlas_source_image is None:
            return "break"
        next_zoom = self._zoom_event(event, self.atlas_zoom)
        if abs(next_zoom - self.atlas_zoom) > 1e-6:
            self.atlas_zoom = next_zoom
            self._render_atlas_canvas()
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

    def _start_atlas_pan(self, event: tk.Event) -> None:
        if self.atlas_source_image is None:
            return
        self.atlas_drag_last = (event.x, event.y)
        self.atlas_canvas.configure(cursor="fleur")

    def _drag_atlas_pan(self, event: tk.Event) -> str:
        if self.atlas_source_image is None or self.atlas_drag_last is None:
            return "break"
        last_x, last_y = self.atlas_drag_last
        self.atlas_offset_x += event.x - last_x
        self.atlas_offset_y += event.y - last_y
        self.atlas_drag_last = (event.x, event.y)
        self._render_atlas_canvas()
        return "break"

    def _end_atlas_pan(self, _event: tk.Event) -> None:
        self.atlas_drag_last = None
        self.atlas_canvas.configure(cursor="")

    # ─── Recipe save / load ──────────────────────────────────────────────

    def _save_recipe(self) -> None:
        initial = str(self.current_recipe_path or "")
        file_path = filedialog.asksaveasfilename(
            title="Сохранить рецепт",
            defaultextension=RECIPE_SUFFIX,
            initialfile=initial,
            filetypes=[("JSON", "*.json")],
        )
        if not file_path:
            return
        payload = {
            "tool": "Cliff Forge Desktop",
            "version": 2,
            "mode": "manual",
            "request": self.build_request(),
        }
        Path(file_path).write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
        self.current_recipe_path = Path(file_path)
        self._add_recent_recipe(file_path)
        self.is_dirty = False
        self._update_title()
        self._set_status(f"Рецепт сохранён: {file_path}")

    def _load_recipe(self) -> None:
        file_path = filedialog.askopenfilename(
            title="Загрузить рецепт",
            filetypes=[("JSON", "*.json"), ("Все файлы", "*.*")],
        )
        if not file_path:
            return
        self._load_recipe_from(file_path)

    def _load_recipe_from(self, file_path: str) -> None:
        try:
            payload = json.loads(Path(file_path).read_text(encoding="utf-8"))
        except Exception as error:  # noqa: BLE001
            messagebox.showerror(WINDOW_TITLE, f"Не удалось прочитать рецепт:\n{error}")
            return

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
            self.texture_color_overlay_var.set(bool(request.get("texture_color_overlay", False)))
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

            self._apply_materials_payload(request.get("materials", {}), textures)

            map_payload = request.get("map")
            if map_payload:
                self.current_map = map_payload
                self.map_w_var.set(map_payload.get("width", self.current_map["width"]))
                self.map_h_var.set(map_payload.get("height", self.current_map["height"]))
                self._draw_map()
        finally:
            self.suspend_events = False

        self.current_recipe_path = Path(file_path)
        self._add_recent_recipe(file_path)
        self.is_dirty = False
        self._update_title()
        self.schedule_full()

    def _apply_materials_payload(self, materials: dict, textures: dict) -> None:
        for slot, defaults in MATERIAL_DEFAULTS.items():
            material = materials.get(slot) or {}
            vars_for_slot = self.material_vars[slot]
            source_key = material.get("source") or ("image" if textures.get(slot) else defaults["source"])
            kind_key = material.get("kind", defaults["kind"])
            vars_for_slot["source"].set(MATERIAL_SOURCE_LABELS.get(source_key, MATERIAL_SOURCE_LABELS[defaults["source"]]))
            vars_for_slot["kind"].set(MATERIAL_KIND_LABELS.get(kind_key, MATERIAL_KIND_LABELS[defaults["kind"]]))
            vars_for_slot["scale"].set(float(material.get("scale", defaults["scale"])))
            vars_for_slot["contrast"].set(float(material.get("contrast", defaults["contrast"])))
            vars_for_slot["crack_amount"].set(float(material.get("crack_amount", defaults["crack_amount"])))
            vars_for_slot["wear"].set(float(material.get("wear", defaults["wear"])))
            vars_for_slot["grain"].set(float(material.get("grain", defaults["grain"])))
            vars_for_slot["edge_darkening"].set(float(material.get("edge_darkening", defaults["edge_darkening"])))
            vars_for_slot["seed"].set(int(material.get("seed", defaults["seed"])))
            vars_for_slot["color_a"].set(material.get("color_a", defaults["color_a"]))
            vars_for_slot["color_b"].set(material.get("color_b", defaults["color_b"]))
            vars_for_slot["highlight"].set(material.get("highlight", defaults["highlight"]))

    def _add_recent_recipe(self, file_path: str) -> None:
        if not file_path:
            return
        if file_path in self.recent_recipes:
            self.recent_recipes.remove(file_path)
        self.recent_recipes.insert(0, file_path)
        del self.recent_recipes[RECENT_RECIPES_LIMIT:]
        self._refresh_recent_recipes()

    def _refresh_recent_recipes(self) -> None:
        if not hasattr(self, "recent_recipes_menu"):
            return
        self.recent_recipes_menu.delete(0, "end")
        self.recent_recipes_menu.add_command(label="Открыть файл…", command=self._load_recipe)
        if self.recent_recipes:
            self.recent_recipes_menu.add_separator()
            for path in self.recent_recipes:
                shortened = path if len(path) <= 60 else "…" + path[-57:]
                self.recent_recipes_menu.add_command(
                    label=shortened,
                    command=lambda p=path: self._load_recipe_from(p),
                )

    # ─── Export ──────────────────────────────────────────────────────────

    def _export_outputs(self) -> None:
        target = filedialog.askdirectory(title="Экспорт файлов")
        if not target:
            return
        export_dir = Path(target)
        if not self.last_manifest or self.last_manifest.get("mode") != "full":
            self.pending_export_dir = export_dir
            self.schedule_full()
            self._set_status("Перед экспортом поставлена в очередь полная сборка…")
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

    # ─── Status / dirty / title ──────────────────────────────────────────

    def _set_status(self, text: str) -> None:
        self.status_var.set(text)

    def _mark_dirty(self) -> None:
        if not self.is_dirty:
            self.is_dirty = True
            self._update_title()

    def _update_title(self) -> None:
        recipe = self.current_recipe_path.name if self.current_recipe_path else "(без имени)"
        dirty = " ●" if self.is_dirty else ""
        self.root.title(f"{WINDOW_TITLE} — {recipe}{dirty}")

    # ─── Keyboard shortcuts ──────────────────────────────────────────────

    def _bind_shortcuts(self) -> None:
        self.root.bind_all("<F5>", lambda _e: self.schedule_full())
        self.root.bind_all("<F6>", lambda _e: self.schedule_draft())
        self.root.bind_all("<Control-s>", lambda _e: self._save_recipe())
        self.root.bind_all("<Control-S>", lambda _e: self._save_recipe())
        self.root.bind_all("<Control-o>", lambda _e: self._load_recipe())
        self.root.bind_all("<Control-O>", lambda _e: self._load_recipe())
        self.root.bind_all("<Control-e>", lambda _e: self._export_outputs())
        self.root.bind_all("<Control-E>", lambda _e: self._export_outputs())
        self.root.bind_all("<Control-z>", lambda _e: self._undo_map())
        self.root.bind_all("<Control-Z>", lambda _e: self._undo_map())
        self.root.bind_all("<Control-y>", lambda _e: self._redo_map())
        self.root.bind_all("<Control-Y>", lambda _e: self._redo_map())
        self.root.bind_all("<Control-Shift-z>", lambda _e: self._redo_map())
        self.root.bind_all("<Control-Shift-Z>", lambda _e: self._redo_map())
        # Tools (single-key shortcuts only when no entry/scale has focus)
        for key, tool in (("b", TOOL_BRUSH), ("e", TOOL_ERASER), ("f", TOOL_FILL)):
            self.root.bind_all(f"<KeyPress-{key}>", lambda evt, t=tool: self._on_tool_shortcut(evt, t))
        self.root.bind_all("<KeyPress-r>", self._on_seed_shortcut)
        # Variant tab switch
        self.root.bind_all("<Control-Key-1>", lambda _e: self.right_notebook.select(0))
        self.root.bind_all("<Control-Key-2>", lambda _e: self.right_notebook.select(1))
        self.root.bind_all("<Control-Key-3>", lambda _e: self.right_notebook.select(2))

    def _on_tool_shortcut(self, event: tk.Event, tool: str) -> None:
        if isinstance(event.widget, (tk.Entry, ttk.Entry, tk.Text)):
            return
        self._select_tool(tool)

    def _on_seed_shortcut(self, event: tk.Event) -> None:
        if isinstance(event.widget, (tk.Entry, ttk.Entry, tk.Text)):
            return
        self._randomize_seed()


# ─── Entry ───────────────────────────────────────────────────────────────────

def main() -> None:
    root = tk.Tk()
    CliffForgeApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
