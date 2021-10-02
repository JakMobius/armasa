#version 410 core
precision highp float;

uniform vec2 u_screen_size;

uniform vec3 u_camera_position;
uniform vec3 u_camera_width_vector;
uniform vec3 u_camera_height_vector;
uniform vec3 u_camera_focus;

uniform isamplerBuffer u_index_buffer;
uniform samplerBuffer u_float_buffer;

uniform int u_entry_index;

out vec4 color;

const float pi = 3.1415926535897932384626433832795;

const float infinity = 1.0 / 0.0;
const float epsilon = 0.0001;
const int max_reflections = 3;
const int max_tree_depth = 16;

const int HITTABLE_LIST_TYPE = 0;
const int HITTABLE_SPHERE_TYPE = 1;
const int HITTABLE_TRIANGLE_TYPE = 2;

const int MATERIAL_METAL = 0;
const int MATERIAL_LAMBERTIAN = 1;
const int MATERIAL_LAMBERTIAN_LIGHT = 2;

struct HitRecord {
	float dist;
	vec3 normal;
	vec3 point;
	int material;
};

HitRecord hit_record;
vec3 ray_source;
vec3 ray_direction;
int hittable_index_stack[max_tree_depth];
int hittable_child_index_stack[max_tree_depth];
int stack_size;

bool intersect_triangle(vec3 point_a, vec3 point_b, vec3 point_c);
bool intersect_sphere(vec3 sphere_position, float sphere_radius);

void hittable_triangle_hit(int index);
void hittable_sphere_hit(int index);
void hittable_list_hit(int index);
void hittable_hit(int index);

bool material_lambertian_reflect(bool has_light);
bool material_metal_reflect();

bool material_reflect(int index);
void trace_rays();

uniform float time;
out vec4 fragment;

uint rand_index;

// A single iteration of Bob Jenkins' One-At-A-Time hashing algorithm.
uint hash(uint x) {
	x += (x << 10u);
	x ^= (x >>  6u);
	x += (x <<  3u);
	x ^= (x >> 11u);
	x += (x << 15u);
	return x;
}

// Compound versions of the hashing algorithm.
uint hash(uvec2 v) {return hash( rand_index++ ^ v.x ^ hash(v.y)                         );}
uint hash(uvec3 v) {return hash( rand_index++ ^ v.x ^ hash(v.y) ^ hash(v.z)             );}
uint hash(uvec4 v) {return hash( rand_index++ ^ v.x ^ hash(v.y) ^ hash(v.z) ^ hash(v.w) );}

// Construct a float with half-open range [0:1] using low 23 bits.
// All zeroes yields 0.0, all ones yields the next smallest representable value below 1.0.
float floatConstruct( uint m ) {
	const uint ieeeMantissa = 0x007FFFFFu; // binary32 mantissa bitmask
	const uint ieeeOne      = 0x3F800000u; // 1.0 in IEEE binary32

	m &= ieeeMantissa;                     // Keep only mantissa bits (fractional part)
	m |= ieeeOne;                          // Add fractional part to 1.0

	float  f = uintBitsToFloat( m );       // Range [1:2]
	return f - 1.0;                        // Range [0:1]
}

// Pseudo-random value in half-open range [0:1].
float random(float x) { return floatConstruct(hash(floatBitsToUint(x))); }
float random(vec2  v) { return floatConstruct(hash(floatBitsToUint(v))); }
float random(vec3  v) { return floatConstruct(hash(floatBitsToUint(v))); }
float random(vec4  v) { return floatConstruct(hash(floatBitsToUint(v))); }

vec2 random_unit_vec2() {
	float a = random(ray_source) * pi;
	return vec2(cos(a), sin(a));
}

vec3 random_unit_vec3() {
	vec2 u = random_unit_vec2();
	float s = random(ray_source) * 4 - 1;
	bool f = s > 1;
	if(f) s -= 2;
	float c = sqrt(1 - s * s);
	if(f) c = -c;
	return vec3(c * u, s);
}

bool intersect_triangle(vec3 point_a, vec3 point_b, vec3 point_c) {
	vec3 edge1 = point_b - point_a;
	vec3 edge2 = point_c - point_a;
	vec3 h = cross(ray_direction, edge2);
	float a = dot(edge1, h);

	if (a > -epsilon && a < epsilon) {
		return false; // This ray is parallel to this triangle.
	}

	float f = 1.0 / a;
	vec3 s = ray_source - point_a;
	float u = f * dot(s, h);

	if (u < 0.0 || u > 1.0) return false;

	vec3 q = cross(s, edge1);
	float v = f * dot(ray_direction, q);

	if (v < 0.0 || u + v > 1.0) return false;

	// At this stage we can compute t to find out where the intersection point is on the line.

	float t = f * dot(edge2, q);

	if (t > epsilon && t < hit_record.dist) // ray intersection
	{
		hit_record.dist = t;
		hit_record.point = ray_source + ray_direction * t;
		hit_record.normal = cross(edge1, edge2);
		hit_record.normal /= length(hit_record.normal);

		if(dot(hit_record.normal, ray_direction) > 0) hit_record.normal = -hit_record.normal;

//		hit_record->set_normal_orientation(ray_direction);
//		hit_record->front_hit = true;
//		hit_record->surf_x = 0;
//		hit_record->surf_y = 0;
		return true;
	} else {
		// This means that there is a line intersection but not a ray intersection.
		return false;
	}
}

bool intersect_sphere(vec3 sphere_position, float sphere_radius) {
	vec3 c_o = ray_source - sphere_position;
	float rd_c_o_dot = dot(ray_direction, c_o);
	float sq_c_0_length = dot(c_o, c_o);
	float disc = sphere_radius * sphere_radius - (sq_c_0_length - rd_c_o_dot * rd_c_o_dot);

	if (disc < 0) return false;

	disc = sqrt(disc);

	float b = -dot(ray_direction, c_o);
	float d1 = b - disc;
	float d2 = b + disc;
	float d = -1;

	if (d1 > 0 && (d2 > d1 || d2 < 0)) {
		d = d1;
	} else if (d2 > 0 && (d1 > d2 || d1 < 0)) {
		d = d2;
	} else {
		return false;
	}

	if(d > hit_record.dist) return false;

	vec3 point = ray_source + d * ray_direction;

	//	hit_record->set_normal_orientation(ray_direction);
	hit_record.point = point;
	hit_record.dist = d;
	hit_record.normal = (point - sphere_position) / sphere_radius;

	if(dot(hit_record.normal, ray_direction) > 0) hit_record.normal = -hit_record.normal;

	//	get_surface_coords(point, hit_record->surf_x, hit_record->surf_y);
	return true;
}

void hittable_triangle_hit(int index) {
	stack_size--;
	vec3 point_a = vec3(
		texelFetch(u_float_buffer, index + 0).r,
		texelFetch(u_float_buffer, index + 1).r,
		texelFetch(u_float_buffer, index + 2).r
	);
	vec3 point_b = vec3(
		texelFetch(u_float_buffer, index + 3).r,
		texelFetch(u_float_buffer, index + 4).r,
		texelFetch(u_float_buffer, index + 5).r
	);
	vec3 point_c = vec3(
		texelFetch(u_float_buffer, index + 6).r,
		texelFetch(u_float_buffer, index + 7).r,
		texelFetch(u_float_buffer, index + 8).r
	);

	if(intersect_triangle(point_a, point_b, point_c)) {
		hit_record.material = texelFetch(u_index_buffer, index + 1).r;
	}
}

void hittable_sphere_hit(int index) {
	stack_size--;

	vec3 sphere_position = vec3(
		texelFetch(u_float_buffer, index).r,
		texelFetch(u_float_buffer, index + 1).r,
		texelFetch(u_float_buffer, index + 2).r
	);
	float sphere_radius = texelFetch(u_float_buffer, index + 3).r;

	if(intersect_sphere(sphere_position, sphere_radius)) {
		hit_record.material = texelFetch(u_index_buffer, index + 1).r;
	}
}

void hittable_list_hit(int index) {

	int stack_index = stack_size - 1;
	int current_child_index = hittable_child_index_stack[stack_index];
	int children_count = texelFetch(u_index_buffer, index + 1).r;

	if(current_child_index == children_count) {
		stack_size--;
		return;
	}

	hittable_child_index_stack[stack_index] = current_child_index + 1;

	int first_child_index = index + 2;
	int children_index = texelFetch(u_index_buffer, first_child_index + current_child_index).r;

	hittable_index_stack[stack_size] = children_index;
	hittable_child_index_stack[stack_size] = 0;
	stack_size++;
}

void material_metal_reflect(int index) {
	vec4 material_color = vec4(
		texelFetch(u_float_buffer, index).r,
		texelFetch(u_float_buffer, index + 1).r,
		texelFetch(u_float_buffer, index + 2).r,
		1.0
	);
	float fuzziness = texelFetch(u_float_buffer, index + 3).r;

	color *= material_color;
	ray_direction -= hit_record.normal * dot(ray_direction, hit_record.normal) * 2;

	vec3 random_vec = vec3(
		random(ray_source),
		random(ray_source),
		random(ray_source)
	);

	ray_direction += fuzziness * random_vec;

	ray_direction /= length(ray_direction);
	float projection = dot(ray_direction, hit_record.normal);

	if(projection < 0) {
		ray_direction -= hit_record.normal * projection * 2;
	}

	ray_direction /= length(ray_direction);
}

bool material_lambertian_reflect(int index, bool has_light) {
	vec4 material_color = vec4(
		texelFetch(u_float_buffer, index).r,
		texelFetch(u_float_buffer, index + 1).r,
		texelFetch(u_float_buffer, index + 2).r,
		1.0
	);

	color *= material_color;

	if(has_light) return true;

	ray_direction = random_unit_vec3();
	float projection = dot(ray_direction, hit_record.normal);
	if(projection < 0) ray_direction -= hit_record.normal * projection * 2;
	ray_direction /= length(ray_direction);

	return false;
}

void hittable_hit(int index) {
	int hittable_type = texelFetch(u_index_buffer, index).r;

	switch(hittable_type) {
		case HITTABLE_LIST_TYPE:     hittable_list_hit(index);     break;
		case HITTABLE_SPHERE_TYPE:   hittable_sphere_hit(index);   break;
		case HITTABLE_TRIANGLE_TYPE: hittable_triangle_hit(index); break;
	}
}

bool material_reflect(int index) {
	int material_type = texelFetch(u_index_buffer, index).r;

	switch(material_type) {
		case MATERIAL_METAL: 	  		material_metal_reflect(index); return false;
		case MATERIAL_LAMBERTIAN: 		material_lambertian_reflect(index, false); return false;
		case MATERIAL_LAMBERTIAN_LIGHT: material_lambertian_reflect(index, true); return true;
	}

	return false;
}

void trace_rays() {
	color = vec4(1, 1, 1, 1);
	int reflections = 0;
	while(reflections++ < max_reflections) {

		hit_record.dist = infinity;
		hittable_index_stack[0] = u_entry_index;
		hittable_child_index_stack[0] = 0;
		stack_size = 1;

		int tree_steps = 0;
		while(stack_size > 0 && tree_steps < 16) {
			hittable_hit(hittable_index_stack[stack_size - 1]);
		}

		if(stack_size != 0) {
			// Error state
			color = vec4(1.0, 0.0, 0.0, 1.0);
			return;
		}

		if(isinf(hit_record.dist)) {
			// Didn't hit anything
			//color *= vec4(ray_direction, 1);
			color = vec4(0, 0, 0, 0);
			return;
		}

		ray_source += ray_direction * hit_record.dist;
		if(material_reflect(hit_record.material)) {
			// Hit a light source
			return;
		}
		ray_direction /= length(ray_direction);
		ray_source += ray_direction * epsilon;
	}

	// Reflection limit exceeded
	color = vec4(0, 0, 0, 0);
}

void main( void ) {
	vec2 position = gl_FragCoord.xy / u_screen_size * 2 - vec2(1, 1);

	vec4 r_color;

	float samples = 1;

	for(int i = 0; i < samples; i++) {
		ray_source = u_camera_position;
		ray_direction = u_camera_focus + u_camera_width_vector * position.x + u_camera_height_vector * position.y;
		ray_direction /= length(ray_direction);
		trace_rays();
		r_color += color / samples;
	}
	color = r_color;
}
