class_name CliffData
extends Resource

## Описание одного типа клифа: текстура, регион в атласе, смещение.

@export var atlas_texture: Texture2D = null
## Область в атласе (пиксели).
@export var region: Rect2 = Rect2()
## Смещение спрайта от центра тайла.
@export var offset: Vector2 = Vector2.ZERO
## Масштаб спрайта.
@export var scale: Vector2 = Vector2(0.05, 0.05)
