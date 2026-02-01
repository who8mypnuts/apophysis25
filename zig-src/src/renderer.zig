const std = @import("std");
const rl = @import("raylib");
const flame = @import("flame.zig");
const colors = @import("colors.zig");

pub const RenderPixel = struct {
    r: f32,
    g: f32,
    b: f32,
    counter: f32, // Changed to f32 for easier GPU texture mapping
};

    // Matches the layout in render.cs
    // Must be kept in sync with flame.Xform and render.cs struct
    pub const XformGPU = extern struct {
        a: f32, b: f32, c: f32, d: f32, e: f32, f: f32,
        weight: f32,
        color: f32,
        linear: f32, sinusoidal: f32, spherical: f32, swirl: f32,
        horseshoe: f32, polar: f32, handkerchief: f32, heart: f32,
        disc: f32, spiral: f32, hyperbolic: f32, diamond: f32,
        ex: f32, julia: f32, bent: f32, waves: f32,
        fisheye: f32, popcorn: f32, exponential: f32, power: f32,
        cosine: f32, rings: f32, fan: f32, eyefish: f32,
        bubble: f32, cylinder: f32, noise: f32, blur: f32,
        gaussian_blur: f32, radial_blur: f32, pie: f32, ngon: f32,
        curl: f32, rectangles: f32, tangent: f32, square: f32,
        rays: f32, blade: f32, secant: f32, twintrian: f32,
        cross: f32,
        
        // New vars
        julian: f32, julian_power: f32, julian_dist: f32,
        
        // Single float padding to align to 52 floats (208 bytes, div 16)
        padding: f32 = 0.0,
    };

    pub const PointGPU = extern struct {
        x: f32, y: f32, c: f32,
        padding: f32 = 0.0,
    };

    pub const RenderState = struct {
        width: i32,
        height: i32,
        allocator: std.mem.Allocator,
        histogram: []RenderPixel, 
        
        // Internal state for the chaos game
        current_point: flame.Point,
        rng: std.Random.DefaultPrng,
        
        gpu_enabled: bool = false,
        scale: f32 = 100.0,
        gamma: f32 = 2.2,
        brightness: f32 = 1.0,
        vibrancy: f32 = 1.0,
    
    // Buffer for clearing and syncing
    zero_buffer: []f32,
    counter_buffer: []f32,

    gpu_histogram_tex: rl.Texture2D,
    tonemap_shader: rl.Shader,
    
    u_gamma_loc: i32,
    u_brightness_loc: i32,
    u_vibrancy_loc: i32,
    u_log_max_hits_loc: i32,
    
    render_texture: rl.RenderTexture2D, // Final output
    
    // Compute resources
    compute_shader: u32,
    blit_shader: u32,
    xform_buffer_id: u32,
    point_buffer_id: u32,
    histogram_buffer_id: u32,
    palette_buffer_id: u32,
    
    // Compute Uniform Locations
    u_num_xforms_loc: i32,
    u_num_iters_loc: i32,
    u_scale_loc: i32,
    u_seed_loc: i32,
    u_width_loc: i32,
    u_height_loc: i32,

    // Blit Uniforms
    u_blit_gamma_loc: i32,
    u_blit_brightness_loc: i32,
    u_blit_vibrancy_loc: i32,
    u_blit_max_hits_loc: i32,

    const NUM_PARTICLES = 1024 * 128; // Standard particle count for GPU iteration

    pub fn init(allocator: std.mem.Allocator, width: i32, height: i32) !RenderState {
        const hist_size = @as(usize, @intCast(width * height));
        const hist = try allocator.alloc(RenderPixel, hist_size);
        
        // Zero out
        for (hist) |*p| {
            p.r = 0;
            p.g = 0;
            p.b = 0;
            p.counter = 0;
        }

        const f_size = @as(usize, @intCast(width)) * @as(usize, @intCast(height));
        const zero_buf = try allocator.alloc(f32, f_size);
        @memset(zero_buf, 0);

        // Initialize Raylib resources
        // Histogram GPU Texture (Float)
        // We use PixelFormat.uncompressed_r32 for R32F (required for NVIDIA atomic float)
        const img = rl.Image{
            .data = zero_buf.ptr,
            .width = width,
            .height = height,
            .mipmaps = 1,
            .format = rl.PixelFormat.uncompressed_r8g8b8a8,
        };
        const tex = try rl.loadTextureFromImage(img);
        
        const shader = try rl.loadShader(null, "src/shaders/tonemap.fs");
        
        const rt = try rl.loadRenderTexture(width, height);

        // --- Compute Shader Loading ---
        // Need null-terminated string for rlCompileShader
        const cs_code_raw = try std.fs.cwd().readFileAlloc(allocator, "src/shaders/render.cs", 1024 * 1024);
        defer allocator.free(cs_code_raw);
        const cs_code = try allocator.dupeZ(u8, cs_code_raw);
        defer allocator.free(cs_code);
        
        const cs_id = rl.gl.rlCompileShader(cs_code, 0x91B9); // RL_COMPUTE_SHADER = 0x91B9
        const compute_prog = rl.gl.rlLoadComputeShaderProgram(cs_id);

        const blit_code_raw = try std.fs.cwd().readFileAlloc(allocator, "src/shaders/blit.cs", 1024 * 1024);
        defer allocator.free(blit_code_raw);
        const blit_code = try allocator.dupeZ(u8, blit_code_raw);
        defer allocator.free(blit_code);
        const blit_cs_id = rl.gl.rlCompileShader(blit_code, 0x91B9);
        const blit_prog = rl.gl.rlLoadComputeShaderProgram(blit_cs_id);

        // --- Buffers ---
        // Transform buffer (dynamic size, max 128 for now)
        const xf_buf_id = rl.gl.rlLoadShaderBuffer(128 * @sizeOf(XformGPU), null, 0x88E8); // RL_DYNAMIC_DRAW = 0x88E8
        
        // Histogram SSBO (4 floats per pixel: r, g, b, c)
        const hist_size_bytes = hist_size * 4 * @sizeOf(f32);
        const hist_buf_id = rl.gl.rlLoadShaderBuffer(@intCast(hist_size_bytes), null, 0x88E8); // RL_DYNAMIC_DRAW

        // Palette SSBO (256 * vec4)
        const pal_buf_id = rl.gl.rlLoadShaderBuffer(256 * 4 * @sizeOf(f32), null, 0x88E8);

        // Point buffer (persistent particles)
        const points = try allocator.alloc(PointGPU, NUM_PARTICLES);
        defer allocator.free(points);
        for (points, 0..) |*p, i| {
            p.x = 0; p.y = 0; p.c = 0;
            // Diagnostic: spread them a bit
            p.x = @floatFromInt(i % 10);
        }
        const pt_buf_id = rl.gl.rlLoadShaderBuffer(NUM_PARTICLES * @sizeOf(PointGPU), points.ptr, 0x88E8);

        const self = RenderState{
            .width = width,
            .height = height,
            .allocator = allocator,
            .histogram = hist,
            .current_point = flame.Point{ .x = 0, .y = 0, .c = 0 },
            .rng = std.Random.DefaultPrng.init(0),
            
            .gpu_histogram_tex = tex,
            .tonemap_shader = shader,
            .u_gamma_loc = rl.getShaderLocation(shader, "uGamma"),
            .u_brightness_loc = rl.getShaderLocation(shader, "uBrightness"),
            .u_vibrancy_loc = rl.getShaderLocation(shader, "uVibrancy"),
            .u_log_max_hits_loc = rl.getShaderLocation(shader, "uLogMaxHits"),
            .render_texture = rt,

            .compute_shader = compute_prog,
            .xform_buffer_id = xf_buf_id,
            .point_buffer_id = pt_buf_id,

            .blit_shader = blit_prog,
            .histogram_buffer_id = hist_buf_id,
            .palette_buffer_id = pal_buf_id,

            .u_num_xforms_loc = rl.getShaderLocation(rl.Shader{ .id = compute_prog, .locs = null }, "uNumXforms"),
            .u_num_iters_loc = rl.getShaderLocation(rl.Shader{ .id = compute_prog, .locs = null }, "uNumIterations"),
            .u_scale_loc = rl.getShaderLocation(rl.Shader{ .id = compute_prog, .locs = null }, "uScale"),
            .u_seed_loc = rl.getShaderLocation(rl.Shader{ .id = compute_prog, .locs = null }, "uSeed"),
            .u_width_loc = rl.getShaderLocation(rl.Shader{ .id = compute_prog, .locs = null }, "uWidth"),
            .u_height_loc = rl.getShaderLocation(rl.Shader{ .id = compute_prog, .locs = null }, "uHeight"),

            .u_blit_gamma_loc = rl.getShaderLocation(rl.Shader{ .id = blit_prog, .locs = null }, "uGamma"),
            .u_blit_brightness_loc = rl.getShaderLocation(rl.Shader{ .id = blit_prog, .locs = null }, "uBrightness"),
            .u_blit_vibrancy_loc = rl.getShaderLocation(rl.Shader{ .id = blit_prog, .locs = null }, "uVibrancy"),
            .u_blit_max_hits_loc = rl.getShaderLocation(rl.Shader{ .id = blit_prog, .locs = null }, "uMaxHits"),
            
            .zero_buffer = zero_buf,
            .counter_buffer = try allocator.alloc(f32, f_size),
        };
        return self;
    }

    pub fn deinit(self: *RenderState) void {
        self.allocator.free(self.zero_buffer);
        self.allocator.free(self.counter_buffer);
        rl.unloadTexture(self.gpu_histogram_tex);
        rl.unloadShader(self.tonemap_shader);
        rl.unloadRenderTexture(self.render_texture);

        rl.gl.rlUnloadShaderBuffer(self.xform_buffer_id);
        rl.gl.rlUnloadShaderBuffer(self.point_buffer_id);
        rl.gl.rlUnloadShaderBuffer(self.histogram_buffer_id);
        rl.gl.rlUnloadShaderBuffer(self.palette_buffer_id);
        
        // Note: rlgl doesn't have a direct unload for compute programs easily, 
        // but we can assume Raylib cleanup or just leave it for now.
        
        self.allocator.free(self.histogram);
    }

    pub fn upload_palette(self: *RenderState, palette: []const colors.Color) void {
        var gpu_pal: [256][4]f32 = undefined;
        for (palette, 0..) |c, i| {
            gpu_pal[i][0] = c.r;
            gpu_pal[i][1] = c.g;
            gpu_pal[i][2] = c.b;
            gpu_pal[i][3] = 1.0;
        }
        rl.gl.rlUpdateShaderBuffer(self.palette_buffer_id, &gpu_pal, gpu_pal.len * 4 * @sizeOf(f32), 0);
    }

    pub fn reset_histogram(self: *RenderState) void {
        for (self.histogram) |*p| {
            p.r = 0; p.g = 0; p.b = 0; p.counter = 0;
        }
        // Zero out the SSBO by uploading the zero buffer
        const total_bytes = @as(usize, @intCast(self.width)) * @as(usize, @intCast(self.height)) * 4 * @sizeOf(f32);
        @memset(self.counter_buffer, 0);
        
        var bytes_cleared: usize = 0;
        const chunk_bytes = self.counter_buffer.len * @sizeOf(f32);
        
        while (bytes_cleared < total_bytes) {
            const current_chunk = @min(chunk_bytes, total_bytes - bytes_cleared);
            rl.gl.rlUpdateShaderBuffer(self.histogram_buffer_id, self.counter_buffer.ptr, @intCast(current_chunk), @intCast(bytes_cleared));
            bytes_cleared += current_chunk;
        }
    }

    pub fn render_iterations(self: *RenderState, f: flame.Flame, iterations: usize) void {
        if (self.gpu_enabled) {
            self.render_gpu_iterations(f);
            return;
        }

        const random = self.rng.random();
        
        const scale = self.scale;
        const cx: f32 = @as(f32, @floatFromInt(self.width)) / 2.0;
        const cy: f32 = @as(f32, @floatFromInt(self.height)) / 2.0;

        for (0..iterations) |_| {
            f.iterate(&self.current_point, random);
            
            // Map to screen coordinates
            const sx = (self.current_point.x * scale) + cx;
            const sy = cy - (self.current_point.y * scale); 

            if (sx >= 0 and sx < @as(f32, @floatFromInt(self.width)) and
                sy >= 0 and sy < @as(f32, @floatFromInt(self.height))) {
                
                const x_idx = @as(i32, @intFromFloat(sx));
                const y_idx = @as(i32, @intFromFloat(sy));
                
                // Safety check
                if (x_idx >= 0 and x_idx < self.width and y_idx >= 0 and y_idx < self.height) {
                    const idx = @as(usize, @intCast(y_idx * self.width + x_idx));
                    
                    // Color accumulation
                    const color = f.palette.getColor(self.current_point.c);
                    
                    self.histogram[idx].counter += 1.0;
                    self.histogram[idx].r += color.r;
                    self.histogram[idx].g += color.g;
                    self.histogram[idx].b += color.b;
                }
            }
        }
    }

    pub fn render_gpu_iterations(self: *RenderState, f: flame.Flame) void {
        const num_xforms = @min(@as(u32, @intCast(f.xforms.len)), 128);
        if (num_xforms == 0) return;

        // 1. Prepare Transforms
        var gpu_xforms: [128]XformGPU = undefined;
        for (f.xforms, 0..) |xf, i| {
            if (i >= 128) break;
            gpu_xforms[i] = XformGPU{
                .a = xf.a, .b = xf.b, .c = xf.c, .d = xf.d, .e = xf.e, .f = xf.f,
                .weight = xf.weight,
                .color = xf.color,
                .linear = xf.linear, .sinusoidal = xf.sinusoidal, .spherical = xf.spherical, .swirl = xf.swirl,
                .horseshoe = xf.horseshoe, .polar = xf.polar, .handkerchief = xf.handkerchief, .heart = xf.heart,
                .disc = xf.disc, .spiral = xf.spiral, .hyperbolic = xf.hyperbolic, .diamond = xf.diamond,
                .ex = xf.ex, .julia = xf.julia, .bent = xf.bent, .waves = xf.waves,
                .fisheye = xf.fisheye, .popcorn = xf.popcorn, .exponential = xf.exponential, .power = xf.power,
                .cosine = xf.cosine, .rings = xf.rings, .fan = xf.fan, .eyefish = xf.eyefish,
                .bubble = xf.bubble, .cylinder = xf.cylinder, .noise = xf.noise, .blur = xf.blur,
                .gaussian_blur = xf.gaussian_blur, .radial_blur = xf.radial_blur, .pie = xf.pie, .ngon = xf.ngon,
                .curl = xf.curl, .rectangles = xf.rectangles, .tangent = xf.tangent, .square = xf.square,
                .rays = xf.rays, .blade = xf.blade, .secant = xf.secant, .twintrian = xf.twintrian,
                .cross = xf.cross,
                
                .julian = xf.julian, 
                .julian_power = xf.julian_power, 
                .julian_dist = xf.julian_dist,
            };
        }

        // 2. Upload to SSBO
        const buf_size = @as(usize, num_xforms) * @sizeOf(XformGPU);
        rl.gl.rlUpdateShaderBuffer(self.xform_buffer_id, &gpu_xforms, @as(u32, @intCast(buf_size)), 0);

        // 3. Dispatch Compute
        rl.gl.rlEnableShader(self.compute_shader);
        
        // Bind 4 Buffers
        rl.gl.rlBindShaderBuffer(self.xform_buffer_id, 0);
        rl.gl.rlBindShaderBuffer(self.point_buffer_id, 1);
        rl.gl.rlBindShaderBuffer(self.histogram_buffer_id, 2);
        rl.gl.rlBindShaderBuffer(self.palette_buffer_id, 3);

        // Set Uniforms
        const num_xf = @as(i32, @intCast(num_xforms));
        const iters_per_thread: i32 = 100; // Boosted for GPU throughput
        const seed = @as(f32, @floatFromInt(self.rng.random().int(u16)));
        
        // Raylib's rlSetUniform uses internal enum: FLOAT=0, INT=4
        const type_int = 4; // SHADER_UNIFORM_INT
        const type_float = 0; // SHADER_UNIFORM_FLOAT

        rl.gl.rlSetUniform(self.u_num_xforms_loc, &num_xf, type_int, 1); 
        rl.gl.rlSetUniform(self.u_num_iters_loc, &iters_per_thread, type_int, 1);
        rl.gl.rlSetUniform(self.u_scale_loc, &self.scale, type_float, 1);
        rl.gl.rlSetUniform(self.u_seed_loc, &seed, type_float, 1);
        rl.gl.rlSetUniform(self.u_width_loc, &self.width, type_int, 1);
        rl.gl.rlSetUniform(self.u_height_loc, &self.height, type_int, 1);

        rl.gl.rlComputeShaderDispatch(NUM_PARTICLES / 256, 1, 1);
        rl.gl.rlDisableShader();
    }
    pub fn update_and_draw_gpu(self: *RenderState) void {
        // Find max_hits
        var max_hits: f32 = 1.0;
        if (!self.gpu_enabled) {
            for (self.histogram) |p| {
                if (p.counter > max_hits) max_hits = p.counter;
            }
        } else {
            max_hits = 10000.0; 
        }

        rl.beginTextureMode(self.render_texture);
        rl.clearBackground(rl.Color.black);

        if (self.gpu_enabled) {
            // Run BLIT Compute Shader: SSBO -> Texture
            rl.gl.rlEnableShader(self.blit_shader);
            rl.gl.rlBindShaderBuffer(self.histogram_buffer_id, 2);
            rl.gl.rlBindShaderBuffer(self.palette_buffer_id, 3);
            // Bind Texture as Image for writing. (uncompressed_r8g8b8a8 = 7)
            rl.gl.rlBindImageTexture(self.gpu_histogram_tex.id, 0, 7, false);
            
            const type_float = @as(i32, 0); // SHADER_UNIFORM_FLOAT
            rl.gl.rlSetUniform(self.u_blit_gamma_loc, &self.gamma, type_float, 1);
            rl.gl.rlSetUniform(self.u_blit_brightness_loc, &self.brightness, type_float, 1);
            rl.gl.rlSetUniform(self.u_blit_vibrancy_loc, &self.vibrancy, type_float, 1);
            rl.gl.rlSetUniform(self.u_blit_max_hits_loc, &max_hits, type_float, 1);

            rl.gl.rlComputeShaderDispatch(@intCast(@divTrunc(self.width, 16) + 1), @intCast(@divTrunc(self.height, 16) + 1), 1);
            rl.gl.rlDisableShader();
        }
        
        // Final draw: gpu_histogram_tex (populated by blit) to render_texture
        const w = @as(f32, @floatFromInt(self.width));
        const h = @as(f32, @floatFromInt(self.height));
        
        rl.drawTextureRec(
            self.gpu_histogram_tex,
            rl.Rectangle.init(0, 0, w, -h), // y-flip for render texture
            rl.Vector2.init(0, 0),
            rl.Color.white
        );

        rl.endTextureMode();
    }

    // Helper to get a pixel buffer for Raylib (CPU Fallback)
    pub fn get_texture_data(self: *RenderState, out_pixels: []u8) void {
        // out_pixels is expected to be Width * Height * 4 (RGBA)
        // Simple tone mapping: log(hits)
        const size = @as(usize, @intCast(self.width * self.height));
        var max_hits: f32 = 1.0;
        
        // Find max (for normalization) - can be optimized
        for (self.histogram) |p| {
            if (p.counter > max_hits) max_hits = p.counter;
        }
        
        const log_max = if (max_hits > 1.1) std.math.log10(1.0 + max_hits) else 1.0;

        const inv_gamma = 1.0 / self.gamma;
        const brightness = self.brightness;
        const vibrancy = self.vibrancy;

        for (0..size) |i| {
            const pixel = self.histogram[i];
            const idx = i * 4;
            
            if (pixel.counter > 0) {
                const count_f = pixel.counter;
                const log_val = std.math.log10(1.0 + count_f);
                const alpha = log_val / log_max; // [0, 1] density
                
                // Average color
                var r = pixel.r / count_f;
                var g = pixel.g / count_f;
                var b = pixel.b / count_f;
                
                // Apple vibrancy (saturation) - simple approach: mix with average color?
                // For now, let's just stick to the standard log-density equation:
                // Final = AverageColor * (alpha ^ (1/gamma)) * brightness * vibrancy
                
                // Tone mapped alpha
                const tm_alpha = std.math.pow(f32, alpha, inv_gamma) * brightness * vibrancy;
                
                r *= tm_alpha;
                g *= tm_alpha;
                b *= tm_alpha;

                // Clamp
                if (r > 1.0) r = 1.0;
                if (g > 1.0) g = 1.0;
                if (b > 1.0) b = 1.0;

                out_pixels[idx] = @as(u8, @intFromFloat(r * 255.0));     // R
                out_pixels[idx+1] = @as(u8, @intFromFloat(g * 255.0));   // G
                out_pixels[idx+2] = @as(u8, @intFromFloat(b * 255.0));   // B
                out_pixels[idx+3] = 255;        // A
            } else {
                out_pixels[idx] = 0;
                out_pixels[idx+1] = 0;
                out_pixels[idx+2] = 0;
                out_pixels[idx+3] = 255;
            }
        }
    }
};
