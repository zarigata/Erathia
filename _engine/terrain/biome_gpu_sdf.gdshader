shader_type voxel_generator;

// Biome map encoding: R = biome id normalized (0..1), G = distance to edge (0..1)
uniform sampler2D biome_map : source_color, filter_nearest;

uniform float world_size : hint_range(1.0, 64000.0) = 16000.0;
uniform float sea_level = 0.0;
uniform float blend_dist : hint_range(0.0, 1.0) = 0.2;
uniform int biome_count = 20;
uniform float ore_frequency : hint_range(0.001, 0.1) = 0.02;
uniform float ore_threshold : hint_range(0.3, 0.9) = 0.6;
uniform float min_ore_depth : hint_range(5.0, 20.0) = 10.0;

// Biome IDs (must match MapGenerator.Biome / GPU map encoding)
const int BIOME_PLAINS = 0;
const int BIOME_FOREST = 1;
const int BIOME_DESERT = 2;
const int BIOME_SWAMP = 3;
const int BIOME_JUNGLE = 4;
const int BIOME_TUNDRA = 5;
const int BIOME_MARSH = 6;
const int BIOME_MOUNTAIN = 7;
const int BIOME_SAVANNA = 8;
const int BIOME_MUSHROOM = 9;
const int BIOME_ICE_SPIRES = 10;
const int BIOME_VOLCANIC = 11;
const int BIOME_HELLSCAPE = 12;
const int BIOME_BEACH = 13;
const int BIOME_OCEAN = 14;

float hash(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453123).x;
}

float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float n000 = hash(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash(i + vec3(1.0, 1.0, 1.0));

	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);

	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);

	return mix(nxy0, nxy1, f.z) * 2.0 - 1.0;
}

float fbm(vec3 p, float freq, int octaves) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < octaves; i++) {
		value += amplitude * noise3d(p * freq);
		amplitude *= 0.5;
		freq *= 2.0;
	}
	return value;
}

float plains_sdf(vec3 p) {
	return p.y - (fbm(p, 0.003, 4) * 20.0);
}

float forest_sdf(vec3 p) {
	return p.y - (fbm(p, 0.004, 3) * 25.0);
}

float desert_sdf(vec3 p) {
	float dunes = sin(p.x * 0.01) * cos(p.z * 0.01) * 15.0;
	return p.y - (fbm(p, 0.005, 2) * 10.0 + dunes);
}

float swamp_sdf(vec3 p) {
	return p.y - (fbm(p, 0.002, 3) * 8.0 - 5.0);
}

float jungle_sdf(vec3 p) {
	float base = fbm(p, 0.006, 4) * 35.0;
	return p.y - base;
}

float tundra_sdf(vec3 p) {
	return p.y - (fbm(p, 0.003, 3) * 15.0 + 5.0);
}

float marsh_sdf(vec3 p) {
	return p.y - (fbm(p, 0.0025, 3) * 6.0 - 8.0);
}

float mountain_sdf(vec3 p) {
	float n = fbm(p, 0.008, 4);
	return p.y - (abs(n) * 100.0 + n * 50.0);
}

float savanna_sdf(vec3 p) {
	return p.y - (fbm(p, 0.0035, 3) * 18.0);
}

float mushroom_sdf(vec3 p) {
	float m = fbm(p, 0.01, 3);
	return p.y - (m * 30.0 + sin(p.x * 0.02) * 10.0);
}

float ice_spires_sdf(vec3 p) {
	float spires = pow(abs(fbm(p, 0.015, 3)), 2.0) * 120.0;
	return p.y - spires;
}

float volcanic_sdf(vec3 p) {
	float cone = length(p.xz) * 0.5;
	return p.y - (abs(fbm(p, 0.01, 3)) * 80.0 + cone);
}

float hellscape_sdf(vec3 p) {
	float warped = fbm(p + vec3(0.0, p.y * 0.05, 0.0), 0.02, 3) * 60.0;
	return p.y - warped;
}

float beach_sdf(vec3 p) {
	float ripples = fbm(p * 0.02, 0.8, 2) * 1.5;
	float terrace = smoothstep(-3.0, 3.0, p.y - sea_level) * 3.0;
	return (abs(p.y - sea_level) - 1.5) + ripples + terrace;
}

float ocean_sdf(vec3 p) {
	float swell = fbm(p * 0.008, 1.2, 3) * 4.0;
	return (p.y - (sea_level - 18.0)) + swell;
}

float get_biome_sdf(int biome_id, vec3 world_pos) {
	switch (biome_id) {
		case BIOME_PLAINS:
			return plains_sdf(world_pos);
		case BIOME_FOREST:
			return forest_sdf(world_pos);
		case BIOME_DESERT:
			return desert_sdf(world_pos);
		case BIOME_SWAMP:
			return swamp_sdf(world_pos);
		case BIOME_JUNGLE:
			return jungle_sdf(world_pos);
		case BIOME_TUNDRA:
			return tundra_sdf(world_pos);
		case BIOME_MARSH:
			return marsh_sdf(world_pos);
		case BIOME_MOUNTAIN:
			return mountain_sdf(world_pos);
		case BIOME_SAVANNA:
			return savanna_sdf(world_pos);
		case BIOME_MUSHROOM:
			return mushroom_sdf(world_pos);
		case BIOME_ICE_SPIRES:
			return ice_spires_sdf(world_pos);
		case BIOME_VOLCANIC:
			return volcanic_sdf(world_pos);
		case BIOME_HELLSCAPE:
			return hellscape_sdf(world_pos);
		case BIOME_BEACH:
			return beach_sdf(world_pos);
		case BIOME_OCEAN:
			return ocean_sdf(world_pos);
		default:
			return plains_sdf(world_pos);
	}
}

// Material IDs (must match BiomeAwareGenerator and terrain shader)
const int MAT_AIR = 0;
const int MAT_DIRT = 1;
const int MAT_STONE = 2;
const int MAT_IRON_ORE = 3;
const int MAT_SAND = 4;
const int MAT_SNOW = 5;
const int MAT_GRASS = 6;

// Layer thicknesses (SDF units)
const float SURFACE_LAYER_THICKNESS = 4.0;
const float DIRT_LAYER_THICKNESS = 6.0;

// Calculate slope from SDF gradient (approximation for single-voxel context)
// In practice, this will be called per-voxel with neighbor sampling
float calculate_slope_from_gradient(vec3 grad) {
	// Horizontal gradient magnitude (XZ plane)
	return length(vec2(grad.x, grad.z));
}

float get_ore_richness(int biome_id) {
	switch (biome_id) {
		case BIOME_VOLCANIC:
			return 2.0;
		case BIOME_MOUNTAIN:
			return 1.8;
		case BIOME_ICE_SPIRES:
			return 1.5;
		case BIOME_MUSHROOM:
			return 1.3;
		case BIOME_DESERT:
			return 1.2;
		case BIOME_SAVANNA:
			return 1.1;
		case BIOME_PLAINS:
			return 1.0;
		case BIOME_TUNDRA:
			return 1.0;
		case BIOME_JUNGLE:
			return 0.9;
		case BIOME_FOREST:
			return 0.8;
		case BIOME_OCEAN:
			return 0.7;
		case BIOME_SWAMP:
			return 0.6;
		case BIOME_BEACH:
			return 0.5;
		default:
			return 1.0;
	}
}

int get_surface_material(int biome_id, float slope) {
	// High slopes become rock (tan(30°) ≈ 0.577)
	if (slope > 0.577) {
		return MAT_STONE;
	}

	switch (biome_id) {
		case BIOME_DESERT:
		case BIOME_BEACH:
			return MAT_SAND;

		case BIOME_TUNDRA:
		case BIOME_ICE_SPIRES:
			// Blend snow→rock on slopes 20-30° (tan(20°) ≈ 0.364)
			if (slope > 0.364) {
				float blend = (slope - 0.364) / (0.577 - 0.364);
				return (blend > 0.5) ? MAT_STONE : MAT_SNOW;
			}
			return MAT_SNOW;

		case BIOME_VOLCANIC:
		case BIOME_MOUNTAIN:
			return MAT_STONE;

		case BIOME_OCEAN:
			return MAT_SAND;

		case BIOME_PLAINS:
		case BIOME_FOREST:
		case BIOME_JUNGLE:
		case BIOME_SAVANNA:
			// Blend grass→rock on slopes 25-30° (tan(25°) ≈ 0.466)
			if (slope > 0.466) {
				float blend = (slope - 0.466) / (0.577 - 0.466);
				return (blend > 0.5) ? MAT_STONE : MAT_GRASS;
			}
			return MAT_GRASS;

		case BIOME_SWAMP:
		case BIOME_MUSHROOM:
			return MAT_DIRT;

		default:
			return MAT_GRASS;
	}
}

int get_subsurface_material(int biome_id) {
	switch (biome_id) {
		case BIOME_DESERT:
		case BIOME_BEACH:
			return MAT_SAND;
		case BIOME_TUNDRA:
		case BIOME_ICE_SPIRES:
			return MAT_DIRT; // Permafrost
		default:
			return MAT_DIRT;
	}
}

// Material/weight generation entry point
void generate_material(inout float material_weight, vec3 world_position, float sdf_value) {
	vec2 uv = (world_position.xz / world_size) + vec2(0.5);
	vec4 biome_data = texture(biome_map, uv);
	int biome_id = clamp(int(floor(biome_data.r * float(biome_count))), 0, biome_count - 1);

	// Air (positive SDF)
	if (sdf_value > 0.0) {
		material_weight = float(MAT_AIR);
		return;
	}

	// Calculate slope from SDF gradient (sample neighbors)
	// Note: In actual implementation, this requires sampling adjacent voxels
	// For now, approximate from world position noise derivatives
	float step_size = 1.0; // 1 voxel
	float sdf_east = get_biome_sdf(biome_id, world_position + vec3(step_size, 0.0, 0.0));
	float sdf_west = get_biome_sdf(biome_id, world_position - vec3(step_size, 0.0, 0.0));
	float sdf_north = get_biome_sdf(biome_id, world_position + vec3(0.0, 0.0, step_size));
	float sdf_south = get_biome_sdf(biome_id, world_position - vec3(0.0, 0.0, step_size));

	float grad_x = (sdf_east - sdf_west) / (2.0 * step_size);
	float grad_z = (sdf_north - sdf_south) / (2.0 * step_size);
	float slope = sqrt(grad_x * grad_x + grad_z * grad_z);

	// Surface layer
	if (sdf_value > -SURFACE_LAYER_THICKNESS) {
		material_weight = float(get_surface_material(biome_id, slope));
		material_weight = clamp(material_weight, 0.0, 6.0);
		return;
	}

	// Subsurface layer
	if (sdf_value > -(SURFACE_LAYER_THICKNESS + DIRT_LAYER_THICKNESS)) {
		material_weight = float(get_subsurface_material(biome_id));
		material_weight = clamp(material_weight, 0.0, 6.0);
		return;
	}

	// Deep underground - check for ore veins
	if (sdf_value < -(min_ore_depth + SURFACE_LAYER_THICKNESS + DIRT_LAYER_THICKNESS)) {
		float ore_richness = get_ore_richness(biome_id);
		float adjusted_threshold = ore_threshold - (ore_richness - 1.0) * 0.1;
		adjusted_threshold = clamp(adjusted_threshold, 0.3, 0.9);

		// 3D ore noise
		float ore_sample = fbm(world_position, ore_frequency, 2);
		ore_sample = (ore_sample + 1.0) * 0.5; // Normalize to 0-1

		if (ore_sample > adjusted_threshold) {
			material_weight = float(MAT_IRON_ORE);
			material_weight = clamp(material_weight, 0.0, 6.0);
			return;
		}
	}

	// Default: stone
	material_weight = float(MAT_STONE);
	material_weight = clamp(material_weight, 0.0, 6.0);
}

// Combined SDF + Material generation
void generate(inout float sdf, inout float material, vec3 world_position) {
	vec2 uv = (world_position.xz / world_size) + vec2(0.5);
	vec4 biome_data = texture(biome_map, uv);
	int biome_id = clamp(int(floor(biome_data.r * float(max(biome_count, 1)))), 0, biome_count - 1);
	float dist_edge = biome_data.g;

	float base_sdf = get_biome_sdf(biome_id, world_position);

	if (dist_edge < blend_dist) {
		vec2 texel = 1.0 / vec2(textureSize(biome_map, 0));
		vec2 offset = texel;
		float neighbor_sdfs[4];
		neighbor_sdfs[0] = get_biome_sdf(clamp(int(floor(texture(biome_map, uv + vec2(offset.x, 0.0)).r * float(biome_count))), 0, biome_count - 1), world_position);
		neighbor_sdfs[1] = get_biome_sdf(clamp(int(floor(texture(biome_map, uv - vec2(offset.x, 0.0)).r * float(biome_count))), 0, biome_count - 1), world_position);
		neighbor_sdfs[2] = get_biome_sdf(clamp(int(floor(texture(biome_map, uv + vec2(0.0, offset.y)).r * float(biome_count))), 0, biome_count - 1), world_position);
		neighbor_sdfs[3] = get_biome_sdf(clamp(int(floor(texture(biome_map, uv - vec2(0.0, offset.y)).r * float(biome_count))), 0, biome_count - 1), world_position);

		float neighbor_avg = (neighbor_sdfs[0] + neighbor_sdfs[1] + neighbor_sdfs[2] + neighbor_sdfs[3]) * 0.25;
		float blend_factor = dist_edge / blend_dist;
		sdf = mix(neighbor_avg, base_sdf, blend_factor);
	} else {
		sdf = base_sdf;
	}

	generate_material(material, world_position, sdf);
}
