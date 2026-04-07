#include "register_types.h"
#include "chunk_visual_kernels.h"
#include "chunk_generator.h"
#include "mountain_topology_builder.h"
#include "world_prepass_kernels.h"
#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_station_mirny(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
    ClassDB::register_class<ChunkVisualKernels>();
    ClassDB::register_class<ChunkGenerator>();
    ClassDB::register_class<MountainTopologyBuilder>();
    ClassDB::register_class<WorldPrePassKernels>();
}

void uninitialize_station_mirny(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
}

extern "C" {
GDExtensionBool GDE_EXPORT station_mirny_init(
    GDExtensionInterfaceGetProcAddress p_get_proc_address,
    const GDExtensionClassLibraryPtr p_library,
    GDExtensionInitialization *r_initialization
) {
    godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
    init_obj.register_initializer(initialize_station_mirny);
    init_obj.register_terminator(uninitialize_station_mirny);
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init_obj.init();
}
}
