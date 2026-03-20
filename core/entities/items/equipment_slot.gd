class_name EquipmentSlotType
extends RefCounted

## Типы слотов экипировки. Расширяется добавлением значений в enum.

enum Slot {
	HEAD = 0,
	BODY = 1,
	FILTER = 2,
	O2_TANK = 3,
	BATTERY = 4,
	ARMOR = 5,
	UTILITY = 6,
	TOOL = 7,
}

## Ключи локализации для каждого слота.
const SLOT_NAME_KEYS: Dictionary = {
	Slot.HEAD: "EQUIP_SLOT_HEAD",
	Slot.BODY: "EQUIP_SLOT_BODY",
	Slot.FILTER: "EQUIP_SLOT_FILTER",
	Slot.O2_TANK: "EQUIP_SLOT_O2_TANK",
	Slot.BATTERY: "EQUIP_SLOT_BATTERY",
	Slot.ARMOR: "EQUIP_SLOT_ARMOR",
	Slot.UTILITY: "EQUIP_SLOT_UTILITY",
	Slot.TOOL: "EQUIP_SLOT_TOOL",
}

## Символ-заглушка для пустого слота.
const SLOT_ICONS: Dictionary = {
	Slot.HEAD: "H",
	Slot.BODY: "B",
	Slot.FILTER: "F",
	Slot.O2_TANK: "O",
	Slot.BATTERY: "E",
	Slot.ARMOR: "A",
	Slot.UTILITY: "U",
	Slot.TOOL: "T",
}
