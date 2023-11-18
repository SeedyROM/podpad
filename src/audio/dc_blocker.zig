//! A DC blocking filter.
const Self = @This();

x1: f32 = 0.0,
y1: f32 = 0.0,

pub fn init() Self {
    return .{
        .x1 = 0.0,
        .y1 = 0.0,
    };
}

pub fn next(self: *Self, input: f32) f32 {
    var output = input - self.x1 + 0.995 * self.y1;
    self.x1 = input;
    self.y1 = output;
    return output;
}
