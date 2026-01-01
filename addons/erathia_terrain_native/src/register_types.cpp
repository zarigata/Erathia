#include "register_types.h"
#include "test_native_class.h"
#include "native_terrain_generator.h"
#include "native_vegetation_dispatcher.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

void initialize_erathia_terrain_module(ModuleInitializationLevel p_level) {
    UtilityFunctions::print("[Erathia] Initializing module at level: ", (int)p_level);
    
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        UtilityFunctions::print("[Erathia] Skipping initialization (not SCENE level)");
        return;
    }
    
    UtilityFunctions::print("[Erathia] Registering classes...");
    
    ClassDB::register_class<NativeTerrainTest>();
    UtilityFunctions::print("[Erathia] ✓ NativeTerrainTest registered");
    
    ClassDB::register_class<NativeTerrainGenerator>();
    UtilityFunctions::print("[Erathia] ✓ NativeTerrainGenerator registered");
    
    ClassDB::register_class<NativeVegetationDispatcher>();
    UtilityFunctions::print("[Erathia] ✓ NativeVegetationDispatcher registered");
    
    UtilityFunctions::print("[Erathia] === All classes registered successfully ===");
}

void uninitialize_erathia_terrain_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
}

extern "C" {
    GDExtensionBool GDE_EXPORT erathia_terrain_library_init(
        GDExtensionInterfaceGetProcAddress p_get_proc_address,
        const GDExtensionClassLibraryPtr p_library,
        GDExtensionInitialization *r_initialization
    ) {
        godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
        
        init_obj.register_initializer(initialize_erathia_terrain_module);
        init_obj.register_terminator(uninitialize_erathia_terrain_module);
        init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
        
        return init_obj.init();
    }
}
