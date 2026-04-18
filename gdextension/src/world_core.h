#ifndef STATION_MIRNY_WORLD_CORE_H
#define STATION_MIRNY_WORLD_CORE_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace godot {

class WorldCore : public RefCounted {
	GDCLASS(WorldCore, RefCounted)

protected:
	static void _bind_methods();

public:
	Dictionary generate_chunk_packet(int64_t p_seed, Vector2i p_coord, int64_t p_world_version) const;
};

} // namespace godot

#endif
