shader_type spatial;

uniform int MAX_STEPS = 128;
uniform sampler3D grid_tex;
uniform vec3 grid_size = vec3(32);
uniform vec3 vox_size = vec3(1);

varying mat3 NORMALS;

vec3 sign_of_dir(vec3 v) {
    // This function returns +1 for positive components, -1 for negative components, and 0 for zero components
    return sign(v) + vec3(equal(v, vec3(0.0)));
}

void dda_voxel_face_normals(const vec3 rd, const bvec3 mask, const mat3 normals, out vec3 normal, out vec3 tangent, out vec3 binormal) {
    vec3 direction = sign(rd);

    if (mask.x) {
        normal = -direction.x * normals[0];
        tangent = direction.x * normals[2];
        binormal = -normals[1];
        return;
    }

    if (mask.y) {
        normal = -direction.y * normals[1];
        tangent = -direction.y * normals[0];
        binormal = normals[2];
        return;
    }

    normal = -direction.z * normals[2];
    tangent = direction.z * normals[0];
    binormal = -normals[1];
}

float ray_aabb(vec3 min, vec3 max, vec3 ro, vec3 rd) {
    float tmin = 0.0;
    float tmax = 1e30f;

    for (int axis = 0; axis < 3; ++axis) {
        float inv_rd = 1.0 / rd[axis];
        float t1 = (min[axis] - ro[axis]) * inv_rd;
        float t2 = (max[axis] - ro[axis]) * inv_rd;

        float dmin = min(t1, t2);
        float dmax = max(t1, t2);

        tmin = max(dmin, tmin);
        tmax = min(dmax, tmax);
    }

    return (tmax >= tmin) ? tmin : 1e30f;
}

vec4 read_tex(vec3 pos) {
    return texture(grid_tex, pos);
}

vec4 dda(vec3 ro, vec3 rd, out vec3 normal) {
    vec3 world_grid_size = grid_size * vox_size;
    vec3 half_grid_size = world_grid_size * 0.5;
    vec3 grid_lower_bounds = -half_grid_size;
    vec3 grid_upper_bounds = half_grid_size;

    float entry_t = ray_aabb(grid_lower_bounds, grid_upper_bounds, ro, rd);
    if (entry_t == 1e30) {
        normal = vec3(0.0);
        return vec4(0.0);
    }

    vec3 entry_world_pos = ro + rd * (entry_t + 0.0001);
    vec3 entry_pos = (entry_world_pos - grid_lower_bounds) / vox_size;
    vec3 pos = clamp(floor(entry_pos), vec3(0.0), grid_size - vec3(1.0));

    vec3 hit_pos = ro + rd * entry_t;
    const float bias = 0.001;
    bvec3 lower_hit = lessThan(abs(hit_pos - grid_lower_bounds), vec3(bias));
    bvec3 upper_hit = lessThan(abs(hit_pos - grid_upper_bounds), vec3(bias));
    bvec3 mask = bvec3(lower_hit.x || upper_hit.x, lower_hit.y || upper_hit.y, lower_hit.z || upper_hit.z);

    vec3 step = sign_of_dir(rd);
    vec3 delta = abs(1.0 / rd);
    vec3 tmax = ((pos + max(step, vec3(0.0))) - entry_pos) / rd;

    for (int i = 0; i < MAX_STEPS; ++i) {
        vec3 norm_pos = (pos + 0.5) / grid_size;
        vec4 voxel_data = read_tex(norm_pos);

        if (voxel_data.a > 0.01) {
            vec3 tangent, binormal;
            dda_voxel_face_normals(rd, mask, NORMALS, normal, tangent, binormal);
            return vec4(norm_pos, 1.0);
        }

        if (tmax.x < tmax.y) {
            if (tmax.x < tmax.z) {
                pos.x += step.x;
                if (pos.x < 0.0 || pos.x >= grid_size.x) break;
                tmax.x += delta.x;
                mask = bvec3(true, false, false);
            } else {
                pos.z += step.z;
                if (pos.z < 0.0 || pos.z >= grid_size.z) break;
                tmax.z += delta.z;
                mask = bvec3(false, false, true);
            }
        } else {
            if (tmax.y < tmax.z) {
                pos.y += step.y;
                if (pos.y < 0.0 || pos.y >= grid_size.y) break;
                tmax.y += delta.y;
                mask = bvec3(false, true, false);
            } else {
                pos.z += step.z;
                if (pos.z < 0.0 || pos.z >= grid_size.z) break;
                tmax.z += delta.z;
                mask = bvec3(false, false, true);
            }
        }
    }

    normal = vec3(0.0);
    return vec4(0.0);
}

varying vec3 vertex_ls;
varying mat3 model_view_matrix;

void vertex() {
    vertex_ls = VERTEX;
    model_view_matrix = mat3(MODELVIEW_MATRIX);
    NORMALS[0] = normalize(MODELVIEW_MATRIX[0].xyz);
    NORMALS[1] = normalize(MODELVIEW_MATRIX[1].xyz);
    NORMALS[2] = normalize(MODELVIEW_MATRIX[2].xyz);
}

void fragment() {
    vec3 ro = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
    vec3 rd = normalize(vertex_ls - ro);

    vec4 hit = dda(ro, rd, NORMAL);
    if (hit.a != 1.0) {
        discard;
    }

    vec4 vox_info = read_tex(hit.rgb);
    ALBEDO = vox_info.rgb;
}
