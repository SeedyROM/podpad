const std = @import("std");
const util = @import("util.zig");
const Self = @This();

const ClipType = enum {
    /// Soft clipping using the hyperbolic tangent function.
    tanh,
    /// Soft clipping using an exponential function.
    exponential,
    /// Hard clipping using a diode function.
    diode,
};

gain: f32 = 1.0,
bias: f32 = 0.0,
clip_type: ClipType = .diode,

const one_third: f32 = 1.0 / 3.0;
const two_thirds: f32 = 2.0 / 3.0;

pub fn next(self: *const Self, value: f32) f32 {
    // Scale the input value by the gain and add the bias.
    var x = value * self.gain + self.bias;

    // Clip the value.
    switch (self.clip_type) {
        .tanh => {
            // Just use the hyperbolic tangent function, simple and fast.
            x = std.math.tanh(x);
        },
        // TODO(SeedyROM): This is broken as fuck.
        .diode => {
            // Positive part of the step function.
            if (x <= one_third) {
                x = 2.0 * x;
            } else if (x > one_third and x <= two_thirds) {
                x = (-3.0 * (x * x)) + (4.0 * x) - one_third;
            } else if (x > two_thirds) {
                x = 1.0;
            }
            // Negative part of the step function.
            else if (x >= -one_third) {
                x = 2.0 * x;
            } else if (x < -one_third and x >= -two_thirds) {
                x = (3.0 * (x * x)) - (4.0 * x) + one_third;
            } else if (x < -two_thirds) {
                x = -1.0;
            }
        },
        .exponential => {
            // Exponential step function.
            if (x > 0.0) {
                x = -1 + @exp(x);
            } else if (x < 0.0) {
                x = 1 + @exp(-x);
            } else {
                x = 0.0;
            }
        },
    }

    // Remove the bias and scale the value back to the original range.
    return (x - self.bias) / self.gain;
}
