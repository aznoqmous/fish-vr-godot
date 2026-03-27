shader_type spatial;
render_mode world_vertex_coords, cull_disabled, depth_draw_always;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

group_uniforms Material;
uniform float metallic : hint_range(0, 1, 0.01); 
uniform float roughness : hint_range(0, 1, 0.01); 

group_uniforms Flow;
uniform sampler2D normal_map_texture;
uniform float normal_map_scale = 1.0;
uniform vec2 normal_map_speed;
uniform float normal_map_height_strength;

uniform sampler2D flow_map_texture;
uniform float speed = 1.0;
uniform sampler2D flow_noise_texture;

group_uniforms Surface;
uniform vec3 base_color: source_color;
uniform vec3 depth_color: source_color;

group_uniforms Underwater;
uniform sampler2D water_ground_texture;
uniform float base_opacity : hint_range(0, 1, 0.01);
uniform float water_depth = 1.0;
uniform float depth_coloring_power = 0.1;
uniform float depth_edge_coloring_power = 0.1;
uniform float depth_gradient_size : hint_range(0, 1, 0.01);
uniform float refraction_strength : hint_range(0, 1, 0.01);
uniform float depth_color_ratio : hint_range(0, 1, 0.01);

varying vec3 v_normal;
varying vec2 v_uv;

group_uniforms Boat;
uniform sampler2D boat_texture;
uniform float boat_scale = 1.0;
uniform float world_scale = 1.0;
uniform float boat_rotation = 0.0;
uniform vec3 boat_position;
varying float boat_elevation;

uniform sampler2D boat_trail_texture;
uniform float boat_trail_scale = 1.0;

float linear_depth(float nonlinear_depth, mat4 inv_projection_matrix) {
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		nonlinear_depth = nonlinear_depth * 2.0 - 1.0;
	#endif
	return 1.0 / (nonlinear_depth * inv_projection_matrix[2].w + inv_projection_matrix[3].w);
}


uniform float reflection_dist = 5.0;
group_uniforms Foam;
uniform float foam_dist : hint_range(0, 1, 0.01);
uniform vec4 foam_color : source_color;

vec2 rotate(vec2 v, float radian){
	float x = v.x;
    float y = v.y;
    v.x = x * cos(radian) - y * sin(radian);
    v.y = x * sin(radian) + y * cos(radian);
    return v;
}

vec3 rotate_x(vec3 vert, float angle) {
	float s = sin(angle);
	float c = cos(angle);

	// [cos - sin, sin + cos]
	return vec3(vert.x, vert.y * c - vert.z * s, vert.y * s + vert.z * c );
}

vec3 rotate_y(vec3 vert, float angle) {
	float s = sin(angle);
	float c = cos(angle);

	// [cos - sin, sin + cos]
	return vec3(vert.x * c - vert.z * s, vert.y, vert.x * s + vert.z * c );
}
vec3 rotate_z(vec3 vert, float angle) {
	float s = sin(angle);
	float c = cos(angle);
	return vec3(vert.x * c - vert.y * s, vert.x * s + vert.y * c, vert.z);
}

float get_edge_dist(vec2 screen_uv, mat4 inv_proj_matrix, vec3 vertex, vec3 normal, vec3 view){
	float lineardepth = linear_depth(texture(DEPTH_TEXTURE, screen_uv).r, inv_proj_matrix);
	float selfdepth = -vertex.z;
	float depth_diff = lineardepth - selfdepth;
	return depth_diff * dot(normalize(normal), normalize(-vertex)) / view.z;
}

vec2 view2uv(vec3 position_view_space, mat4 proj_m)
{
	vec4 position_clip_space = proj_m * vec4(position_view_space.xyz, 1.0);
	vec2 position_ndc = position_clip_space.xy / position_clip_space.w;
	return position_ndc.xy * 0.5 + 0.5;
}

float remap(float x, float min1, float max1, float min2, float max2) {
	return ((x - min1) / (max1 - min1) + min2) * (max2 - min2);
}

float remap1(float x, float min1, float max1) {
	return (x - min1) / (max1 - min1);
}

float schlickfresnel(float ior1, float ior2, vec3 view, vec3 norm) {
	float incident = dot(view, norm);
	float reflectance = pow(((ior2 - ior1)/(ior2 + ior1)), 2.0);
	float fresnelincident = reflectance + (1.0 - reflectance) * pow(1.0 - cos(incident), 5.0);
	return(fresnelincident / incident);
}

float edge_fade(vec2 uv, float size) {
	float x1 = clamp(remap1(uv.x, 0.0, size), 0.0, 1.0);
	float x2 = clamp(remap1(uv.x, 1.0, 1.0 - size), 0.0, 1.0);
	float y1 = clamp(remap1(uv.y, 0.0, size), 0.0, 1.0);
	float y2 = clamp(remap1(uv.y, 1.0, 1.0 - size), 0.0, 1.0);
	return x1*x2*y1*y2;
}

uniform sampler2D noise;

void vertex() {

	// BOAT
	vec3 camera_position = CAMERA_POSITION_WORLD;
    vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	vec2 boat_tex_pos = (world_position.xz) / boat_scale - boat_position.xz / world_scale;
	vec2 rotate_boat_tex_pos = rotate(boat_tex_pos, boat_rotation);
	if(rotate_boat_tex_pos.x > -0.5 && rotate_boat_tex_pos.x < 0.5 && rotate_boat_tex_pos.y > -0.5 && rotate_boat_tex_pos.y < 0.5){
		boat_elevation = texture(boat_texture, rotate_boat_tex_pos + vec2(0.5)).r;
	}


	// FLOW MAP
	vec2 normal_uv = UV / normal_map_scale + normal_map_speed * vec2(TIME);
	vec2 flow = texture(flow_map_texture, UV).xy - vec2(0.5);
	float time = TIME * speed;
	float phase_a = fract(time);
	float phase_b = fract(time + 0.5);
	vec3 normal_a = texture(normal_map_texture, normal_uv - flow * phase_a).rgb;
	vec3 normal_b = texture(normal_map_texture, normal_uv - flow * phase_b).rgb;
	float flow_lerp = abs(0.5 - phase_a)  / 0.5;
	VERTEX.y = mix(normal_a, normal_b, flow_lerp).y / 10.0;
	VERTEX.y += texture(noise, UV + vec2(TIME / 1000.0, TIME / 800.0)).r / 10.0;
	
}
uniform float foam_vertex_height;

group_uniforms screen_space_reflection;
uniform bool ssr_enabled = false;
uniform float far_clip = 50.0;
uniform int steps : hint_range(64, 1024, 16) = 512;
uniform float ssr_screen_fade : hint_range(0.01, 0.5, 0.01) = 0.05;

uniform float test_float = 0.0;

void fragment() {
	ROUGHNESS = roughness;
	METALLIC = metallic;
	
	// FLOW MAP
	vec2 normal_uv = UV / normal_map_scale + normal_map_speed * vec2(TIME);
	vec2 flow = texture(flow_map_texture, UV).xy - vec2(0.5);
	float time = TIME * speed;
	float phase_a = fract(time);
	float phase_b = fract(time + 0.5);
	vec3 normal_a = texture(normal_map_texture, normal_uv - flow * phase_a).rgb;
	vec3 normal_b = texture(normal_map_texture, normal_uv - flow * phase_b).rgb;
	
	float flow_lerp = abs(0.5 - phase_a)  / 0.5;
	v_normal = mix(normal_a, normal_b, flow_lerp);
	NORMAL += TANGENT * (v_normal.x - 0.5) * 1.0;
	NORMAL += BINORMAL * (v_normal.y - 0.5) * 1.0;
	
	float distfromedge = get_edge_dist(SCREEN_UV, INV_PROJECTION_MATRIX, VERTEX, NORMAL, VIEW);
	
	vec3 camera_position = CAMERA_POSITION_WORLD;
    vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec3 view_dir = normalize(camera_position - world_position);
	
	vec3 ground_color = texture(water_ground_texture, UV).rgb;
	float edge_ratio = clamp(base_opacity + clamp(pow(distfromedge, depth_gradient_size), 0, water_depth) / water_depth - dot(view_dir, NORMAL) / 20.0, 0, 1);

	ALBEDO = mix(base_color, mix(depth_color, ground_color, depth_coloring_power), dot(view_dir, NORMAL) * depth_color_ratio);
	ALBEDO = mix(ALBEDO, ground_color, (1.0 - pow(edge_ratio, 0.2)) * depth_color_ratio);
	//ALPHA = clamp(distfromedge * depth_edge_coloring_power, 0, 1);
	
	if(distfromedge < foam_dist){
		ALBEDO = mix(ALBEDO, foam_color.xyz, (1.0 - clamp(distfromedge / foam_dist, 0, 1)) * foam_color.a);
		ALPHA = clamp((ALPHA + 1.0 - distfromedge * 10.0), 0, 1);
	}
	
	//ALPHA = 1.0 - boat_elevation;
	
	// SSR
	if(ssr_enabled){
		
		vec3 reflected = -reflect(VIEW, NORMAL);
		vec3 pos = VERTEX;
		int curstep = 0;
		bool finished = false;
		vec2 uv;
		float currentdepth;
		while (curstep < steps) {
			float step_scale = float(curstep + 1) / float(steps);
			float step_dist = step_scale * step_scale * far_clip;
			pos += reflected * step_dist;
			curstep += 1;
			currentdepth = -pos.z;
			uv = view2uv(pos, PROJECTION_MATRIX);
			if (!(uv.x < 1.0 && uv.y < 1.0 && uv.x > 0.0 && uv.y > 0.0)) {
				break;
			}
			float testdepth = linear_depth(texture(DEPTH_TEXTURE, uv).r, INV_PROJECTION_MATRIX);
			if (testdepth < currentdepth) {
				finished = true;
				break;
			}
		}
		if (finished && currentdepth < far_clip * 0.99) {
			ALBEDO *= 1.0 - edge_fade(uv, ssr_screen_fade);
			METALLIC *= 1.0 - edge_fade(uv, ssr_screen_fade);
			EMISSION += texture(SCREEN_TEXTURE, uv).xyz * schlickfresnel(1.0, 1.33, VIEW, NORMAL) * edge_fade(uv, ssr_screen_fade);
		}
	}
	
	// REFRACTION TEST
	//float depth_ratio = clamp(depth_diff, 0, 1);
    //vec2 refraction_offset = v_normal.xz * refraction_strength / 10.0;
    //vec2 refracted_uv = SCREEN_UV + refraction_offset * depth_ratio;
    //vec3 refracted_color = texture(SCREEN_TEXTURE, refracted_uv).rgb;
	
}

//void light() {
	//// Called for every pixel for every light affecting the material.
	//// Uncomment to replace the default light processing function with this one.
//}
