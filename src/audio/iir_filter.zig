//! Implements a state variable filter with the bilinear transform.
const std = @import("std");

const Self = @This();
const iir_filter_log = std.log.scoped(.iir_filter);

const Type = enum {
    lowpass,
    highpass,
    bandpass,
    notch,
    peak,
    lowshelf,
    highshelf,
};

const FilterState = struct {
    x1: f32,
    x2: f32,
    y1: f32,
    y2: f32,

    pub fn init() FilterState {
        return .{
            .x1 = 0.0,
            .x2 = 0.0,
            .y1 = 0.0,
            .y2 = 0.0,
        };
    }

    /// Reset the filter state.
    pub fn reset(self: *FilterState) void {
        self.x1 = 0.0;
        self.x2 = 0.0;
        self.y1 = 0.0;
        self.y2 = 0.0;
    }

    /// Process the given input sample with the given coefficients.
    pub fn next(self: *FilterState, input: f32, coefficients: *Coefficients) f32 {
        var output = coefficients.a0 * input + coefficients.a1 * self.x1 + coefficients.a2 * self.x2 - coefficients.b1 * self.y1 - coefficients.b2 * self.y2;

        self.x2 = self.x1;
        self.x1 = input;
        self.y2 = self.y1;
        self.y1 = output;

        return output;
    }
};

const Coefficients = struct {
    a0: f32,
    a1: f32,
    a2: f32,
    b1: f32,
    b2: f32,

    pub fn init() Coefficients {
        return .{
            .a0 = 0.0,
            .a1 = 0.0,
            .a2 = 0.0,
            .b1 = 0.0,
            .b2 = 0.0,
        };
    }

    /// Update the coefficients based on the given filter type.
    pub fn update(self: *Coefficients, kind: Type, frequency: f32, q: f32, gain: f32, sample_rate: f32) void {
        var w0 = std.math.tau * frequency / sample_rate;
        var alpha = std.math.sin(w0) / (2.0 * q);

        switch (kind) {
            .lowpass => {
                var a0 = 1.0 + alpha;
                self.a0 = (1.0 - std.math.cos(w0)) / a0;
                self.a1 = (1.0 - std.math.cos(w0)) / a0 * 2.0;
                self.a2 = (1.0 - std.math.cos(w0)) / a0;
                self.b1 = (-2.0 * std.math.cos(w0)) / a0;
                self.b2 = (1.0 - alpha) / a0;
            },
            .highpass => {
                var a0 = 1.0 + alpha;
                self.a0 = (1.0 + std.math.cos(w0)) / a0;
                self.a1 = (-2.0 * (1.0 + std.math.cos(w0))) / a0;
                self.a2 = (1.0 + std.math.cos(w0)) / a0;
                self.b1 = (-2.0 * std.math.cos(w0)) / a0;
                self.b2 = (1.0 - alpha) / a0;
            },
            .bandpass => {
                var a0 = 1.0 + alpha;
                self.a0 = alpha / a0;
                self.a1 = 0.0;
                self.a2 = -alpha / a0;
                self.b1 = (-2.0 * std.math.cos(w0)) / a0;
                self.b2 = (1.0 - alpha) / a0;
            },
            .notch => {
                var a0 = 1.0 + alpha;
                self.a0 = 1.0 / a0;
                self.a1 = (-2.0 * std.math.cos(w0)) / a0;
                self.a2 = 1.0 / a0;
                self.b1 = (-2.0 * std.math.cos(w0)) / a0;
                self.b2 = (1.0 - alpha) / a0;
            },
            .peak => {
                var a0 = 1.0 + alpha / q;
                self.a0 = (1.0 + alpha * gain) / a0;
                self.a1 = (-2.0 * std.math.cos(w0)) / a0;
                self.a2 = (1.0 - alpha * gain) / a0;
                self.b1 = (-2.0 * std.math.cos(w0)) / a0;
                self.b2 = (1.0 - alpha / q) / a0;
            },
            .lowshelf => {
                var a0 = 1.0 + alpha;
                self.a0 = (1.0 + std.math.sqrt(2.0 * gain) * alpha + gain) / a0;
                self.a1 = (-2.0 * (gain - 1.0)) / a0;
                self.a2 = (1.0 - std.math.sqrt(2.0 * gain) * alpha + gain) / a0;
                self.b1 = (-2.0 * std.math.cos(w0)) / a0;
                self.b2 = (1.0 - alpha) / a0;
            },
            .highshelf => {
                var a0 = 1.0 + alpha;
                self.a0 = (gain + std.math.sqrt(2.0 * gain) * alpha + 1.0) / a0;
                self.a1 = (2.0 * (1.0 - gain)) / a0;
                self.a2 = (gain - std.math.sqrt(2.0 * gain) * alpha + 1.0) / a0;
                self.b1 = (-2.0 * std.math.cos(w0)) / a0;
                self.b2 = (1.0 - alpha) / a0;
            },
        }
    }
};

coefficients: Coefficients = Coefficients.init(),
frequency: f32 = 1000.0,
gain: f32 = 0.0,
q: f32 = 1.0,
sample_rate: f32 = 44100.0,
state: FilterState = FilterState.init(),
type: Type = .lowpass,

pub fn init(
    kind: Type,
    frequency: f32,
    q: f32,
    gain: f32,
) Self {
    var self = Self{
        .type = kind,
        .frequency = frequency,
        .q = q,
        .gain = gain,
    };

    self.updateCoefficients();

    return self;
}

pub fn setFrequency(self: *Self, frequency: f32) void {
    // If the frequency is negative, log a warning and set it to 0.0
    if (frequency < 0.0) {
        iir_filter_log.debug("Frequency must be positive, given: {}", .{frequency});
        self.frequency = 0.0;
    }

    // If the frequency is the same, do nothing
    if (frequency == self.frequency) {
        return;
    }

    // If the freqency is higher than half the sample rate, return half the sample rate
    if (frequency > self.sample_rate / 2.0) {
        self.frequency = self.sample_rate / 2.0;
    } else {
        self.frequency = frequency;
    }

    // Update the coefficients
    self.updateCoefficients();
}

pub fn setQ(self: *Self, q: f32) void {
    // If the Q is negative, log a warning and set it to 0.0
    if (q < 0.0) {
        iir_filter_log.debug("Q must be positive, given: {}", .{q});
        q = 0.0;
    }

    // If the Q is the same, do nothing
    if (q == self.q) {
        return;
    }

    // Set the Q
    self.q = q;
    self.updateCoefficients();
}

pub fn setGain(self: *Self, gain: f32) void {
    if (self.type != .lowshelf and self.type != .highshelf) {
        iir_filter_log.debug("Gain can only be set for lowshelf and highshelf filters, given: {}", .{self.type});
        return;
    }

    self.gain = gain;
    self.updateCoefficients();
}

pub fn setType(self: *Self, kind: Type) void {
    self.type = kind;
    self.updateCoefficients();
}

pub fn next(self: *Self, input: f32) f32 {
    return self.state.next(input, &self.coefficients);
}

fn updateCoefficients(self: *Self) void {
    self.coefficients.update(self.type, self.frequency, self.q, self.gain, self.sample_rate);
}
