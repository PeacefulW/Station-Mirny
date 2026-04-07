#ifndef CHUNK_VISUAL_KERNELS_H
#define CHUNK_VISUAL_KERNELS_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

class ChunkVisualKernels : public RefCounted {
	GDCLASS(ChunkVisualKernels, RefCounted)

public:
	ChunkVisualKernels();
	~ChunkVisualKernels();

	Dictionary compute_visual_batch(Dictionary p_request) const;

protected:
	static void _bind_methods();
};

} // namespace godot

#endif // CHUNK_VISUAL_KERNELS_H
