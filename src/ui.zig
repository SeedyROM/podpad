const std = @import("std");

const audio = @import("audio.zig");
const renderer = @import("renderer.zig");
const Vec2i = renderer.Vec2i;

var allocator: std.mem.Allocator = undefined;

const sequencer = struct {
    const Pad = struct {
        on: bool = false,
        note: i32 = 0,
        hovered: bool = false,
        position: Vec2i = .{ .x = 0, .y = 0 },
        active: bool = false,

        const size = 16;

        pub fn init(note: i32) Pad {
            return .{
                .on = false,
                .note = note,
                .hovered = false,
                .position = .{ .x = 0, .y = 0 },
                .active = false,
            };
        }

        pub fn draw(self: *Pad, pos: Vec2i) !void {
            const push_up = 2;

            self.position = pos;

            var rect = .{ .x = pos.x, .y = pos.y, .w = size, .h = size };
            if (self.on) {
                if (self.active) {
                    rect.y -= push_up;
                }
                try renderer.drawRect(rect, .{ .r = 255, .g = 255, .b = 255 });
            } else {
                if (self.hovered or self.active) {
                    try renderer.drawRect(rect, .{ .r = 128, .g = 128, .b = 128 });
                } else {
                    try renderer.drawRect(rect, .{ .r = 64, .g = 64, .b = 64 });
                }
            }
        }

        pub fn update(self: *Pad, mouse_position: Vec2i, is_mouse_down: bool) void {
            // Check if the mouse is within the bounds of the pad
            const is_mouse_over = mouse_position.x >= self.position.x and
                mouse_position.x <= self.position.x + size and
                mouse_position.y >= self.position.y and
                mouse_position.y <= self.position.y + size;

            // If the mouse is over the pad, set the hovered flag
            if (is_mouse_over) {
                self.hovered = true;
            } else {
                self.hovered = false;
            }

            // If the mouse is over the pad and the mouse is down, toggle the pad
            if (is_mouse_over and is_mouse_down) {
                self.on = !self.on;
            }
        }
    };

    const Column = struct {
        pads: []Pad,

        pub fn init() !Column {
            var column = .{
                .pads = try allocator.alloc(Pad, 16),
            };

            // Initialize each pad
            for (0..column.pads.len) |i| {
                var pad = Pad.init(@intCast(45 + 16 - i));
                column.pads[i] = pad;
            }

            return column;
        }

        pub fn deinit(
            self: *Column,
        ) void {
            allocator.free(self.pads);
        }

        pub fn draw(self: *Column, pos: Vec2i) !void {
            // Draw each pad in the column vertically spaced out by 24 pixels
            for (0..self.pads.len) |_i| {
                var pad = &self.pads[_i];
                const i = @as(i32, @intCast(_i));
                try pad.draw(.{ .x = pos.x, .y = pos.y + (i * 24) });
            }
        }
    };

    const Pattern = struct {
        columns: []Column,

        /// Initialize an empty pattern
        pub fn init() !Pattern {
            var _pattern = .{
                .columns = try allocator.alloc(Column, 16),
            };

            // Initialize each column
            for (0.._pattern.columns.len) |i| {
                var column = try Column.init();
                _pattern.columns[i] = column;
            }

            return _pattern;
        }

        /// Initialize a random pattern
        pub fn initRandom() !Pattern {
            var _pattern = .{
                .columns = try allocator.alloc(Column, 16),
            };

            // Create a prng
            var prng = std.rand.DefaultPrng.init(@intCast(std.time.microTimestamp()));

            // Initialize each column
            for (_pattern.columns) |*column| {
                column.* = try Column.init(); // Assuming Column.init needs an allocator

                // Generate a random pad index
                const randomPadIndex = prng.random().int(u32) % 16;

                // Set a random pad for the column
                column.*.pads[randomPadIndex].on = true;
            }

            return _pattern;
        }

        pub fn deinit(
            self: *Pattern,
        ) void {
            for (0..self.columns.len) |i| {
                var column = self.columns[i];
                column.deinit();
            }
            allocator.free(self.columns);
        }

        pub fn draw(self: *Pattern, pos: Vec2i) !void {
            // Draw each column in the pattern spaced out by 24 pixels
            for (0..self.columns.len) |_i| {
                var column = &self.columns[_i];
                const i = @as(i32, @intCast(_i));
                try column.draw(.{ .x = pos.x + (i * 24), .y = pos.y });
            }
        }
    };

    var pattern: Pattern = undefined;
    var duration: f32 = 0.0;
    var currentColumn: usize = 0;

    pub fn init() !void {
        pattern = try Pattern.initRandom();
    }

    pub fn deinit() void {
        pattern.deinit();
    }

    pub fn update(mouse_position: Vec2i, is_mouse_down: bool, frame_time: f32) void {
        // Update the sequencer
        for (0..sequencer.pattern.columns.len) |i| {
            var column = &sequencer.pattern.columns[i];
            for (0..column.pads.len) |j| {
                var pad = &column.pads[j];
                pad.update(mouse_position, is_mouse_down);
            }
        }

        // Update the current column and play the notes
        sequencer.duration += frame_time;

        if (sequencer.duration >= 120.0) {
            sequencer.duration = 0.0;
            sequencer.currentColumn += 1;
            if (sequencer.currentColumn >= sequencer.pattern.columns.len) {
                sequencer.currentColumn = 0;
            }

            // Clear the previous column of active pads
            var last_column_index: usize = 0;
            if (sequencer.currentColumn == 0) {
                last_column_index = sequencer.pattern.columns.len - 1;
            } else {
                last_column_index = sequencer.currentColumn - 1;
            }
            var last_column = &sequencer.pattern.columns[last_column_index];
            for (0..last_column.pads.len) |i| {
                var pad = &last_column.pads[i];
                pad.active = false;
                audio.noteOff();
            }

            // Set the current column's pads to active and play the notes
            var column = &sequencer.pattern.columns[sequencer.currentColumn];
            for (0..column.pads.len) |i| {
                var pad = &column.pads[i];
                pad.active = true;
                if (pad.on) {
                    audio.noteOn(pad.note);
                }
            }
        }
    }

    pub fn draw(pos: Vec2i) !void {
        try pattern.draw(pos);
    }
};

const transport = struct {
    const State = enum(u8) {
        Stopped,
        Playing,
    };
};

pub fn init(_allocator: std.mem.Allocator) !void {
    allocator = _allocator;
    try sequencer.init();
}

pub fn deinit() void {
    sequencer.deinit();
}

pub fn update(mouse_position: Vec2i, is_mouse_down: bool, delta: f32) !void {
    sequencer.update(mouse_position, is_mouse_down, delta);
}

pub fn render() !void {
    try sequencer.draw(.{ .x = 16, .y = 16 });
}
