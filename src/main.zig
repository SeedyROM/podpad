const std = @import("std");

const audio = @import("audio.zig");
const renderer = @import("renderer.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var gpa_allocator = gpa.allocator();

pub fn main() !void {
    try renderer.init(gpa_allocator);
    try audio.init(gpa_allocator);
    defer {
        audio.deinit();
        renderer.deinit();
    }

    var clear_color: [3]u8 = .{ 127, 63, 255 };
    var running = true;
    while (running) {
        for (try renderer.events()) |event| {
            switch (event) {
                .quit => running = false,
                .mouse_down => |mouse_down| {
                    if (mouse_down.button == .left) {
                        const x = 30 + @as(f32, @floatFromInt(mouse_down.x)) / 4;
                        audio.setFrequency(x);
                        clear_color[0] = @as(u8, @intCast(@mod(mouse_down.x, 255)));
                        audio.noteOn();
                    }
                },
                .mouse_up => |mouse_up| {
                    if (mouse_up.button == .left) {
                        audio.noteOff();
                    }
                },
                else => {},
            }
        }

        try renderer.clear(clear_color[0], clear_color[1], clear_color[2]);
        renderer.present();

        std.time.sleep(60 * 1_000_000);
    }
}
