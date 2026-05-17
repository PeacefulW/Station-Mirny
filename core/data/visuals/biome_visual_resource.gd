extends Resource
class_name RockVisualResource

@export var top_color: Color = Color(0.72, 0.70, 0.66, 1.0)
@export var face_color: Color = Color(0.45, 0.42, 0.40, 1.0)
@export var back_color: Color = Color(0.22, 0.20, 0.19, 1.0)

@export_range(0.0, 1.0, 0.01) var top_to_face_cutoff: float = 0.62
@export_range(0.0, 1.0, 0.01) var face_to_back_cutoff: float = 0.28

@export_range(0.0, 2.0, 0.05) var ledge_contrast: float = 1.2

@export_range(0.0, 1.0, 0.01) var top_coverage: float = 0.55
@export_range(0.0, 1.0, 0.01) var face_coverage: float = 0.30
@export_range(0.0, 1.0, 0.01) var back_coverage: float = 0.15

@export_range(0.0, 2.0, 0.05) var normal_strength: float = 1.0
