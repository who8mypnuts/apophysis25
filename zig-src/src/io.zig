const std = @import("std");
const flame = @import("flame.zig");
const colors = @import("colors.zig");

// --- Structs for Serialization ---
// We'll define a simpler struct for YAML serialization that maps cleanly to our Flame struct.

// NOTE: For now, we are implementing a basic text-based format or reusing standard Zig serialization if possible,
// but Zig's standard library JSON support is much stronger than YAML. 
// Since the user requested YAML (.flamey), we will implement a simple parser/writer for it,
// or use a library if available. Given we want to avoid complex external deps if possible,
// we might implement a simplified key-value parser for now or a basic YAML subset.

// Actually, "Recycled" users often prefer XML because of existing tools.
// But the user asked for .flamey (YAML) as new format.

// Let's implement a custom simplified YAML-like printer/parser for our specific struct.

pub const IO = struct {
    
    // --- saving ---
    pub fn saveFlam3Yaml(filename: []const u8, f: flame.Flame) !void {
        var file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();
        
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        // Use a large buffer for writing
        const buf = try allocator.alloc(u8, 1024 * 1024);
        var fbs = std.io.fixedBufferStream(buf);
        const writer = fbs.writer();

        try writer.print("flame:\n", .{});
        try writer.print("  gamma: {d:.4}\n", .{f.gamma});
        try writer.print("  brightness: {d:.4}\n", .{f.brightness});
        try writer.print("  vibrancy: {d:.4}\n", .{f.vibrancy});
        try writer.print("  xforms:\n", .{});
        
        for (f.xforms) |xf| {
            try writer.print("    - weight: {d:.4}\n", .{xf.weight});
            try writer.print("      color: {d:.4}\n", .{xf.color});
            try writer.print("      coefs: [{d:.4}, {d:.4}, {d:.4}, {d:.4}, {d:.4}, {d:.4}]\n", .{xf.a, xf.b, xf.c, xf.d, xf.e, xf.f});
            
            // Variations (only print non-zero)
            try writer.print("      variations:\n", .{});
            if (xf.linear != 0) try writer.print("        linear: {d:.4}\n", .{xf.linear});
            if (xf.sinusoidal != 0) try writer.print("        sinusoidal: {d:.4}\n", .{xf.sinusoidal});
            if (xf.spherical != 0) try writer.print("        spherical: {d:.4}\n", .{xf.spherical});
            if (xf.swirl != 0) try writer.print("        swirl: {d:.4}\n", .{xf.swirl});
            if (xf.horseshoe != 0) try writer.print("        horseshoe: {d:.4}\n", .{xf.horseshoe});
            if (xf.polar != 0) try writer.print("        polar: {d:.4}\n", .{xf.polar});
            if (xf.handkerchief != 0) try writer.print("        handkerchief: {d:.4}\n", .{xf.handkerchief});
            if (xf.heart != 0) try writer.print("        heart: {d:.4}\n", .{xf.heart});
            if (xf.disc != 0) try writer.print("        disc: {d:.4}\n", .{xf.disc});
            if (xf.spiral != 0) try writer.print("        spiral: {d:.4}\n", .{xf.spiral});
            if (xf.hyperbolic != 0) try writer.print("        hyperbolic: {d:.4}\n", .{xf.hyperbolic});
            if (xf.diamond != 0) try writer.print("        diamond: {d:.4}\n", .{xf.diamond});
            if (xf.ex != 0) try writer.print("        ex: {d:.4}\n", .{xf.ex});
            if (xf.julia != 0) try writer.print("        julia: {d:.4}\n", .{xf.julia});
            if (xf.bent != 0) try writer.print("        bent: {d:.4}\n", .{xf.bent});
        }
        
        try file.writeAll(fbs.getWritten());
    }
    
    // --- loading ---
    pub fn loadFlam3Yaml(allocator: std.mem.Allocator, filename: []const u8) !flame.Flame {
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();
        
        const size = try file.getEndPos();
        const buffer = try allocator.alloc(u8, size);
        defer allocator.free(buffer);
        
        _ = try file.readAll(buffer);
        
        var f = flame.Flame{
            .xforms = &[_]flame.Xform{}, // Placeholder, will be replaced
            .palette = colors.Palette.initDefault(),
            .gamma = 2.2,
            .brightness = 1.0,
            .vibrancy = 1.0,
        };

        // Pass 1: Count xforms
        var xform_count: usize = 0;
        var iter_count = std.mem.splitSequence(u8, buffer, "\n");
        while (iter_count.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, " \r\t");
            if (std.mem.startsWith(u8, line, "- weight:")) {
                xform_count += 1;
            }
        }
        
        // Allocate exact size
        const xforms = try allocator.alloc(flame.Xform, xform_count);
        // Initialize xforms to default
        for (xforms) |*x| {
            x.* = flame.Xform{};
        }
        f.xforms = xforms;

        var current_idx: usize = 0;
        var in_xform = false;
        
        var iter = std.mem.splitSequence(u8, buffer, "\n");
        while (iter.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, " \r\t");
            if (line.len == 0) continue;
            if (std.mem.startsWith(u8, line, "flame:")) continue;
            
            // Global settings
            if (std.mem.startsWith(u8, line, "gamma:")) {
                f.gamma = try parseFloat(line, "gamma:");
            } else if (std.mem.startsWith(u8, line, "brightness:")) {
                f.brightness = try parseFloat(line, "brightness:");
            } else if (std.mem.startsWith(u8, line, "vibrancy:")) {
                f.vibrancy = try parseFloat(line, "vibrancy:");
            } else if (std.mem.startsWith(u8, line, "xforms:")) {
                 continue;
            } else if (std.mem.startsWith(u8, line, "- weight:")) {
                // New Xform
                if (in_xform) {
                    current_idx += 1;
                }
                in_xform = true;
                
                if (current_idx < xforms.len) {
                    xforms[current_idx].weight = try parseFloat(line, "- weight:");
                }
            } else if (std.mem.startsWith(u8, line, "color:")) {
                 if (in_xform and current_idx < xforms.len) xforms[current_idx].color = try parseFloat(line, "color:");
            } else if (std.mem.startsWith(u8, line, "coefs:")) {
                 if (in_xform and current_idx < xforms.len) {
                    try parseCoefs(line, &xforms[current_idx]);
                 }
            } else if (std.mem.startsWith(u8, line, "variations:")) {
                // context switch
            } else {
                // Try parsing variations
                if (in_xform and current_idx < xforms.len) {
                     // Check if this line actually looks like a variation
                     if (std.mem.indexOf(u8, line, ":") != null) {
                        try parseVariation(line, &xforms[current_idx]);
                     } else {
                         // End of this xform or garbage?
                         // If we hit next xform start ("- weight:") it handles itself, but we are inside loop.
                         // Actually, standard YAML "list items" start with "-".
                         // If we are here, we are just inside an object.
                         // How do we detect END of xform? 
                         // We don't really need to, except to increment index.
                         // BUT wait, if we are at next "- weight:", we need to increment BEFORE processing it.
                         // My logic above increments at the start of "- weight:"? No, I didn't increment!
                     }
                }
            }
            
            // Peek next line check? No, stream.
            // Actually, we should increment idx when we see *next* weight, OR finish.
            // Issue: When do we increment `current_idx`?
            // "weight" is the first field of an xform in our saver.
            // So when we see "- weight:", valid assumption is it's a new xform.
            // But if it's the *first* one, idx is 0. If second, idx is 1.
            // So:
            // init idx = -1? 
            // Or handle idx increment:
            
        }
        
        return f;
    }
    
    // Helpers
    fn parseFloat(line: []const u8, prefix: []const u8) !f32 {
        const val_str = std.mem.trim(u8, line[prefix.len..], " ");
        return std.fmt.parseFloat(f32, val_str);
    }
    
    fn parseCoefs(line: []const u8, xf: *flame.Xform) !void {
        // coefs: [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
        const start = std.mem.indexOf(u8, line, "[");
        const end = std.mem.indexOf(u8, line, "]");
        if (start == null or end == null) return;
        
        const content = line[start.?+1 .. end.?];
        var it = std.mem.splitSequence(u8, content, ",");
        
        var idx: usize = 0;
        while (it.next()) |val| : (idx += 1) {
            const v = std.fmt.parseFloat(f32, std.mem.trim(u8, val, " ")) catch 0.0;
            switch (idx) {
                0 => xf.a = v,
                1 => xf.b = v,
                2 => xf.c = v,
                3 => xf.d = v,
                4 => xf.e = v,
                5 => xf.f = v,
                else => {},
            }
        }
    }
    
    fn parseVariation(line: []const u8, xf: *flame.Xform) !void {
        // format: name: value
        var it = std.mem.splitSequence(u8, line, ":");
        const name_part = it.next() orelse return;
        const val_part = it.next() orelse return;
        
        const name = std.mem.trim(u8, name_part, " ");
        const val = std.fmt.parseFloat(f32, std.mem.trim(u8, val_part, " ")) catch return;
        
        if (std.mem.eql(u8, name, "linear")) xf.linear = val;
        if (std.mem.eql(u8, name, "sinusoidal")) xf.sinusoidal = val;
        if (std.mem.eql(u8, name, "spherical")) xf.spherical = val;
        if (std.mem.eql(u8, name, "swirl")) xf.swirl = val;
        if (std.mem.eql(u8, name, "horseshoe")) xf.horseshoe = val;
        if (std.mem.eql(u8, name, "polar")) xf.polar = val;
        if (std.mem.eql(u8, name, "handkerchief")) xf.handkerchief = val;
        if (std.mem.eql(u8, name, "heart")) xf.heart = val;
        if (std.mem.eql(u8, name, "disc")) xf.disc = val;
        if (std.mem.eql(u8, name, "spiral")) xf.spiral = val;
        if (std.mem.eql(u8, name, "hyperbolic")) xf.hyperbolic = val;
        if (std.mem.eql(u8, name, "diamond")) xf.diamond = val;
        if (std.mem.eql(u8, name, "ex")) xf.ex = val;
        if (std.mem.eql(u8, name, "julia")) xf.julia = val;
        if (std.mem.eql(u8, name, "bent")) xf.bent = val;
    }
    pub fn loadLegacyFlameXml(allocator: std.mem.Allocator, filename: []const u8) !flame.Flame {
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();
        
        const size = try file.getEndPos();
        const buffer = try allocator.alloc(u8, size);
        defer allocator.free(buffer);
        
        _ = try file.readAll(buffer);
        
        var f = flame.Flame{
            .xforms = &[_]flame.Xform{},
            .palette = colors.Palette.initDefault(),
            .gamma = 2.2,
            .brightness = 1.0,
            .vibrancy = 1.0,
        };
        
        // Pass 1: Count xforms
        const xform_count = std.mem.count(u8, buffer, "<xform ");
        
        const xforms = try allocator.alloc(flame.Xform, xform_count);
        f.xforms = xforms;
        
        // Pass 2: Parse
        // Find <flame ...>
        if (findTag(buffer, "flame")) |flame_tag| {
             parseFlameAttrs(flame_tag, &f);
        }
        
        // Find <palette ...> and parse it
        if (findTag(buffer, "palette")) |_| {
             const end_tag = "</palette>";
             if (std.mem.indexOf(u8, buffer, end_tag)) |pal_end_idx| {
                 // We found the tag content start in `pal_tag`, but `findTag` returns the opening tag itself?
                 // Wait, `findTag` implementation: returns buffer[s..s+e]. That is just `<flame ... >`.
                 // So we need to find the content BETWEEN the opening tag and closing tag.
                 
                 // Re-locate opening tag in buffer
                 const needle = "<palette";
                 if (std.mem.indexOf(u8, buffer, needle)) |start_idx| {
                     const gt_idx = std.mem.indexOf(u8, buffer[start_idx..], ">");
                     if (gt_idx) |gt| {
                         const content_start = start_idx + gt + 1;
                         if (content_start < pal_end_idx) {
                             const pal_content = buffer[content_start..pal_end_idx];
                             try parseLegacyPalette(pal_content, &f.palette);
                         }
                     }
                 }
             }
        }

        var idx: usize = 0;
        var pos: usize = 0;
        while (findNextTag(buffer[pos..], "xform")) |res| {
             const tag_content = res.content;
             pos += res.end_pos;
             
             if (idx < xforms.len) {
                 xforms[idx] = flame.Xform{
                     .weight = 0.5,
                     .color = 0.0,
                     .a = 1.0, .b = 0.0, .c = 0.0, .d = 1.0, .e = 0.0, .f = 0.0,
                 };
                 try parseXformAttrs(tag_content, &xforms[idx]);
                 idx += 1;
             }
        }
        
        return f;
    }

    fn parseLegacyPalette(content: []const u8, pal: *colors.Palette) !void {
        var color_idx: usize = 0;
        var current_hex: [6]u8 = undefined;
        var current_hex_len: usize = 0;

        for (content) |c| {
            // hex chars usually 0-9, A-F
            if ((c >= '0' and c <= '9') or (c >= 'A' and c <= 'F') or (c >= 'a' and c <= 'f')) {
                current_hex[current_hex_len] = c;
                current_hex_len += 1;
                
                if (current_hex_len == 6) {
                    if (color_idx < 256) {
                        pal.colors[color_idx] = colors.Color{
                            .r = parseHexFloat(current_hex[0], current_hex[1]),
                            .g = parseHexFloat(current_hex[2], current_hex[3]),
                            .b = parseHexFloat(current_hex[4], current_hex[5]),
                            .a = 1.0,
                        };
                        color_idx += 1;
                    }
                    current_hex_len = 0;
                }
            }
        }
        
        // Auto-generate nodes from the loaded palette
        // Create 16 control nodes spaced evenly
        pal.num_nodes = 16;
        var i: usize = 0;
        while (i < 16) : (i += 1) {
            const pos = @as(f32, @floatFromInt(i)) / 15.0;
            const idx = @as(usize, @intFromFloat(pos * 255.0));
            pal.nodes[i] = colors.ColorNode{
                .pos = pos,
                .color = pal.colors[idx],
            };
        }
    }
    
    fn parseHexFloat(c1: u8, c2: u8) f32 {
        const v1 = parseHexDigit(c1);
        const v2 = parseHexDigit(c2);
        const val = (v1 << 4) | v2;
        return @as(f32, @floatFromInt(val)) / 255.0;
    }
    
    fn parseHexDigit(c: u8) u8 {
        if (c >= '0' and c <= '9') return c - '0';
        if (c >= 'A' and c <= 'F') return c - 'A' + 10;
        if (c >= 'a' and c <= 'f') return c - 'a' + 10;
        return 0;
    }
    
    // Simple XML helpers
    const TagResult = struct {
        content: []const u8,
        end_pos: usize,
    };
    
    fn findTag(buffer: []const u8, tag_name: []const u8) ?[]const u8 {
        var buf: [64]u8 = undefined;
        // needle: <tag_name 
        const needle = std.fmt.bufPrint(&buf, "<{s} ", .{tag_name}) catch return null;
        
        const start = std.mem.indexOf(u8, buffer, needle);
        if (start) |s| {
             const end = std.mem.indexOf(u8, buffer[s..], ">");
             if (end) |e| {
                 return buffer[s..s+e];
             }
        }
        return null;
    }
    
    fn findNextTag(buffer: []const u8, tag_name: []const u8) ?TagResult {
        var buf: [64]u8 = undefined;
        // needle: <tag_name 
        const needle = std.fmt.bufPrint(&buf, "<{s} ", .{tag_name}) catch return null;
        
        const start = std.mem.indexOf(u8, buffer, needle);
        if (start) |s| {
             const end = std.mem.indexOf(u8, buffer[s..], ">");
             if (end) |e| {
                 return TagResult{ .content = buffer[s..s+e], .end_pos = s + e + 1 };
             }
        }
        return null;
    }

    fn parseFlameAttrs(content: []const u8, f: *flame.Flame) void {
         if (getAttrVal(content, "gamma")) |v| f.gamma = std.fmt.parseFloat(f32, v) catch 2.2;
         if (getAttrVal(content, "brightness")) |v| f.brightness = std.fmt.parseFloat(f32, v) catch 1.0;
         if (getAttrVal(content, "vibrancy")) |v| f.vibrancy = std.fmt.parseFloat(f32, v) catch 1.0;
    }
    
    fn parseXformAttrs(content: []const u8, xf: *flame.Xform) !void {
        if (getAttrVal(content, "weight")) |v| xf.weight = try std.fmt.parseFloat(f32, v);
        if (getAttrVal(content, "color")) |v| xf.color = try std.fmt.parseFloat(f32, v);
        
        if (getAttrVal(content, "coefs")) |v| {
             var it = std.mem.splitSequence(u8, v, " ");
             if (it.next()) |s| xf.a = try std.fmt.parseFloat(f32, s);
             if (it.next()) |s| xf.b = try std.fmt.parseFloat(f32, s);
             if (it.next()) |s| xf.c = try std.fmt.parseFloat(f32, s);
             if (it.next()) |s| xf.d = try std.fmt.parseFloat(f32, s);
             if (it.next()) |s| xf.e = try std.fmt.parseFloat(f32, s);
             if (it.next()) |s| xf.f = try std.fmt.parseFloat(f32, s);
        }
        
        var it = std.mem.splitSequence(u8, content, " ");
        while (it.next()) |part| {
            if (std.mem.indexOf(u8, part, "=")) |eq_idx| {
                const key = part[0..eq_idx];
                const val_quoted = part[eq_idx+1..];
                const val_str = std.mem.trim(u8, val_quoted, "\"");
                
                const vnum = std.fmt.parseFloat(f32, val_str) catch continue;
                
                if (std.mem.eql(u8, key, "linear")) xf.linear = vnum;
                if (std.mem.eql(u8, key, "julia")) xf.julia = vnum;
                // Add more variations as needed
            }
        }
    }
    
    fn getAttrVal(content: []const u8, attr: []const u8) ?[]const u8 {
        var buf: [64]u8 = undefined;
        const needle = std.fmt.bufPrint(&buf, "{s}=\"", .{attr}) catch return null;
        if (std.mem.indexOf(u8, content, needle)) |idx| {
            const start = idx + needle.len;
            if (std.mem.indexOf(u8, content[start..], "\"")) |end| {
                return content[start .. start+end];
            }
        }
        return null;
    }
};

test "save and load flamey" {
    const allocator = std.testing.allocator;
    
    // Create test flame
    var xforms = try allocator.alloc(flame.Xform, 2);
    
    xforms[0] = flame.Xform{
        .weight = 0.5,
        .color = 0.1,
        .a = 1.0, .b = 0.0, .c = 0.0, .d = 1.0, .e = 0.0, .f = 0.0,
    };
    xforms[1] = flame.Xform{
        .weight = 1.0,
        .color = 0.9,
        .a = 0.5, .b = 0.5, .c = -0.5, .d = 0.5, .e = 1.0, .f = 1.0,
        .julia = 2.0, // Test a variation
    };
    
    const f = flame.Flame{
        .gamma = 2.2,
        .brightness = 4.0,
        .vibrancy = 1.0,
        .palette = colors.Palette.initDefault(),
        .xforms = xforms,
    };
    
    // Save
    try IO.saveFlam3Yaml("test_out.flamey", f);
    
    // Load
    const f2 = try IO.loadFlam3Yaml(allocator, "test_out.flamey");
    defer allocator.free(f2.xforms);
    
    // Verify
    try std.testing.expectApproxEqAbs(f.gamma, f2.gamma, 0.001);
    try std.testing.expectEqual(f.xforms.len, f2.xforms.len);
    try std.testing.expectApproxEqAbs(f.xforms[0].weight, f2.xforms[0].weight, 0.001);
    try std.testing.expectApproxEqAbs(f.xforms[1].a, f2.xforms[1].a, 0.001);
    try std.testing.expectApproxEqAbs(f.xforms[1].julia, f2.xforms[1].julia, 0.001);

    allocator.free(xforms);
}

test "load legacy flame xml" {
    const allocator = std.testing.allocator;
    const test_xml =
        \\<flame name="Test" gamma="2.5" brightness="3.0" >
        \\   <xform weight="0.8" color="0.5" coefs="1 0 0 1 0 0" linear="1" />
        \\   <xform weight="0.2" color="0.1" coefs="0.5 0 0 0.5 0.5 0.5" julia="1.5" />
        \\</flame>
    ;
    
    // Write detailed test file
    try std.fs.cwd().writeFile(.{ .sub_path = "test_legacy.flame", .data = test_xml });
    
    const f = try IO.loadLegacyFlameXml(allocator, "test_legacy.flame");
    defer allocator.free(f.xforms);
    
    try std.testing.expectApproxEqAbs(f.gamma, 2.5, 0.001);
    try std.testing.expectApproxEqAbs(f.brightness, 3.0, 0.001);
    try std.testing.expectEqual(f.xforms.len, 2);
    try std.testing.expectApproxEqAbs(f.xforms[0].weight, 0.8, 0.001);
    try std.testing.expectApproxEqAbs(f.xforms[0].linear, 1.0, 0.001);
    try std.testing.expectApproxEqAbs(f.xforms[1].julia, 1.5, 0.001);
}

test "load legacy flame palette" {
    const allocator = std.testing.allocator;
    // Minimal palette string with red, green, blue hexes (just for testing parsing)
    // We repeats colors to fill 256 entries roughly or just enough to test
    // "FF0000" (Red), "00FF00" (Green), "0000FF" (Blue)
    const test_xml =
        \\<flame name="TestPal" >
        \\   <xform weight="1" color="0" coefs="1 0 0 1 0 0" />
        \\   <palette count="256" format="RGB">
        \\      FF000000FF000000FFFF000000FF000000FF
        \\   </palette>
        \\</flame>
    ;
    
    try std.fs.cwd().writeFile(.{ .sub_path = "test_pal.flame", .data = test_xml });
    
    const f = try IO.loadLegacyFlameXml(allocator, "test_pal.flame");
    defer allocator.free(f.xforms);
    
    // Check first few colors
    // FF0000 -> R=1, G=0, B=0
    try std.testing.expectApproxEqAbs(f.palette.colors[0].r, 1.0, 0.001);
    try std.testing.expectApproxEqAbs(f.palette.colors[0].g, 0.0, 0.001);
    try std.testing.expectApproxEqAbs(f.palette.colors[0].b, 0.0, 0.001);

    // 00FF00 -> R=0, G=1, B=0
    try std.testing.expectApproxEqAbs(f.palette.colors[1].r, 0.0, 0.001);
    try std.testing.expectApproxEqAbs(f.palette.colors[1].g, 1.0, 0.001);

    // Check node generation
    try std.testing.expectEqual(f.palette.num_nodes, 16);
    // Node 0 should match color 0
    try std.testing.expectApproxEqAbs(f.palette.nodes[0].color.r, 1.0, 0.001);
}

