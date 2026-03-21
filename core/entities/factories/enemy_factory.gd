class_name EnemyFactory
extends RefCounted

const BASIC_ENEMY_SCRIPT: GDScript = preload("res://core/entities/fauna/basic_enemy.gd")
const ENEMY_TEXTURE: Texture2D = preload("res://assets/sprites/fauna/enemy_cleaner_32.png")

func create_basic_enemy(spawn_pos: Vector2, balance: EnemyBalance) -> CharacterBody2D:
	if not balance:
		return null
	var enemy := CharacterBody2D.new()
	enemy.collision_layer = 4
	enemy.collision_mask = 1 | 2
	enemy.global_position = spawn_pos

	var visual := Sprite2D.new()
	visual.name = "Visual"
	visual.texture = ENEMY_TEXTURE
	visual.scale = Vector2(1.5, 1.5)
	enemy.add_child(visual)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(48, 48)
	collision.shape = shape
	enemy.add_child(collision)

	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = balance.max_health
	enemy.add_child(health)

	enemy.set_script(BASIC_ENEMY_SCRIPT)
	enemy.balance = balance
	enemy.add_to_group("enemies")
	return enemy
