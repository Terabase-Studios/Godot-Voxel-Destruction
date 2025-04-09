shader_type spatial;

#define MAX_STEPS 150
#define MAX_DISTANCE 50.0
#define MAX_VOXELS 500000
#define SURFACE_DISTANCE 0.01

uniform float half_size = 0.5;
uniform int vox_count;
uniform vec3 vox_positions[MAX_VOXELS];
uniform vec3 vox_colors[MAX_VOXELS];
uniform int vox_color_induces[MAX_VOXELS];

// Signed Distance Function for a Box
float SignedDistanceBox(vec3 position) {
    vec3 box_distance = abs(position) - half_size;
    float outside_distance = length(max(box_distance, 0.0));
    float inside_distance = min(max(box_distance.x, max(box_distance.y, box_distance.z)), 0.0);
    return outside_distance + inside_distance;
}

// Signed Distance Function that returns both distance and voxel index
vec2 SignedDistance(vec3 position) {
    float min_dist = 1e6; // Initialize with a large value
    int closest_voxel_index = -1;
    for (int i = 0; i < vox_count; i++) {
        vec3 pos = vox_positions[i] * half_size - size*2.0;
        float dist = SignedDistanceBox(position - pos);
        if (dist < min_dist) {
            min_dist = dist;
            closest_voxel_index = i;
        }
    }
    return vec2(min_dist, float(closest_voxel_index));
}

// Estimate surface normal using central differences
vec3 CalculateNormals(vec3 position) {
    vec2 epsilon = vec2(0.01, 0.0);
    float dist1 = SignedDistance(position + epsilon.xyy).x;
    float dist2 = SignedDistance(position - epsilon.xyy).x;
    float dist3 = SignedDistance(position + epsilon.yxy).x;
    float dist4 = SignedDistance(position - epsilon.yxy).x;
    float dist5 = SignedDistance(position + epsilon.yyx).x;
    float dist6 = SignedDistance(position - epsilon.yyx).x;
    vec3 gradient = vec3(
        dist1 - dist2,
        dist3 - dist4,
        dist5 - dist6
    );
    return normalize(gradient);
}

// Ray marching algorithm to find the intersection with the object
vec2 RayMarch(vec3 ray_origin, vec3 ray_direction) {
    float distance_from_origin = 0.0;
    int hit_voxel_index = -1;
    for (int step = 0; step < MAX_STEPS; step++) {
        vec3 current_position = ray_origin + ray_direction * distance_from_origin;
        vec2 scene_info = SignedDistance(current_position);
        float scene_distance = scene_info.x;
        int voxel_index = int(scene_info.y);
        distance_from_origin += scene_distance;
        if (scene_distance < SURFACE_DISTANCE) {
            hit_voxel_index = voxel_index;
            break;
        }
        if (distance_from_origin > MAX_DISTANCE) {
            break;
        }
    }
    return vec2(distance_from_origin, float(hit_voxel_index));
}

// Varying data passed between vertex and fragment stages
varying vec3 vertex_local_space;
varying mat3 model_view_rotation_matrix;

void vertex() {
    vertex_local_space = VERTEX;
    model_view_rotation_matrix = mat3(MODELVIEW_MATRIX);
}

void fragment() {
    vec3 ray_origin = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
    vec3 ray_direction = normalize(vertex_local_space - ray_origin);
    vec2 march_result = RayMarch(ray_origin, ray_direction);
    float hit_distance = march_result.x;
    int hit_voxel_index = int(march_result.y);
    if (hit_distance > MAX_DISTANCE || hit_voxel_index == -1) {
        discard;
    }
    vec3 hit_position = ray_origin + ray_direction * hit_distance;
    vec3 surface_normal = model_view_rotation_matrix * CalculateNormals(hit_position);
    NORMAL = surface_normal;

    // Retrieve the color of the closest voxel
    vec3 voxel_color = vox_colors[vox_color_induces[hit_voxel_index]];
    ALBEDO = voxel_color;
}
