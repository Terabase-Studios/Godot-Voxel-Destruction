shader_type spatial;

#define MAX_STEPS 150
#define MAX_DISTANCE 50.0
#define SURFACE_DISTANCE 0.001
uniform float half_size = 0.5;

// Signed Distance Function for a Box
float SignedDistanceBox(vec3 position) {
    vec3 box_distance = abs(position) - half_size;
    float outside_distance = length(max(box_distance, 0.0));
    float inside_distance = min(max(box_distance.x, max(box_distance.y, box_distance.z)), 0.0);
    return outside_distance + inside_distance;
}

// Estimate surface normal using central differences
vec3 CalculateNormals(vec3 position) {
    vec2 epsilon = vec2(0.01, 0.0);
    vec3 gradient = vec3(
        SignedDistanceBox(position) - SignedDistanceBox(position - epsilon.xyy),
        SignedDistanceBox(position) - SignedDistanceBox(position - epsilon.yxy),
        SignedDistanceBox(position) - SignedDistanceBox(position - epsilon.yyx)
    );
    return normalize(gradient);
}

// Ray marching algorithm to find the intersection with the object
float RayMarch(vec3 ray_origin, vec3 ray_direction) {
    float distance_from_origin = 0.0;
    for (int step = 0; step < MAX_STEPS; step++) {
        vec3 current_position = ray_origin + ray_direction * distance_from_origin;
        float scene_distance = SignedDistanceBox(current_position);
        distance_from_origin += scene_distance;
        if (abs(scene_distance) < SURFACE_DISTANCE || distance_from_origin > MAX_DISTANCE) {
            break;
        }
    }
    return distance_from_origin;
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
    float hit_distance = RayMarch(ray_origin, ray_direction);
    if (hit_distance > MAX_DISTANCE) {
        discard;
    }
    vec3 hit_position = ray_origin + ray_direction * hit_distance;
    vec3 surface_normal = model_view_rotation_matrix * CalculateNormals(hit_position);
    NORMAL = surface_normal;
}
