const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_audio.h");
});

/// A simple ADSR envelope generator.
const ADSR = struct {
    attack_time: f32,
    decay_time: f32,
    sustain_level: f32,
    release_time: f32,
    sample_rate: f32,

    state: ADSR.State,
    envelope_value: f32,
    time_since_note_on: f32,
    time_since_note_off: f32,

    const State = enum { attack, decay, sustain, release, off };

    pub fn init(sample_rate: f32) ADSR {
        return ADSR{
            .attack_time = 0.01,
            .decay_time = 0.1,
            .sustain_level = 0.1,
            .release_time = 0.1,
            .sample_rate = sample_rate,
            .state = .off,
            .envelope_value = 0.0,
            .time_since_note_on = 0.0,
            .time_since_note_off = 0.0,
        };
    }

    pub fn noteOn(self: *ADSR) void {
        self.state = .attack;
        self.time_since_note_on = 0.0;
    }

    pub fn noteOff(self: *ADSR) void {
        self.state = .release;
        self.time_since_note_off = 0.0;
    }

    /// Calculate the next envelope value.
    pub fn next(self: *ADSR) f32 {
        const sample_increment = 1.0 / self.sample_rate;

        switch (self.state) {
            .attack => {
                self.envelope_value += sample_increment / self.attack_time;
                self.time_since_note_on += sample_increment;

                if (self.envelope_value >= 1.0 or self.time_since_note_on >= self.attack_time) {
                    self.envelope_value = 1.0;
                    self.state = .decay;
                }
            },
            .decay => {
                self.envelope_value -= sample_increment / self.decay_time * (1.0 - self.sustain_level);
                self.time_since_note_on += sample_increment;

                if (self.envelope_value <= self.sustain_level or self.time_since_note_on >= (self.attack_time + self.decay_time)) {
                    self.envelope_value = self.sustain_level;
                    self.state = .sustain;
                }
            },
            .sustain => {
                // In sustain state, the envelope value stays constant
                self.envelope_value = self.sustain_level;
            },
            .release => {
                self.envelope_value -= sample_increment / self.release_time * self.sustain_level;
                self.time_since_note_off += sample_increment;

                if (self.envelope_value <= 0.0 or self.time_since_note_off >= self.release_time) {
                    self.envelope_value = 0.0;
                    self.state = .off;
                }
            },
            .off => {},
        }

        return self.envelope_value;
    }
};

/// Implements a state variable filter with the bilinear transform.
pub const IIRFilter = struct {
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

    type: Type = .lowpass,
    frequency: f32 = 1000.0,
    q: f32 = 1.0,
    gain: f32 = 0.0,
    sample_rate: f32 = 44100.0,
    coefficients: Coefficients = Coefficients.init(),
    state: FilterState = FilterState.init(),

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
};

/// A poly BLEP multiple mode oscillator.
/// Based on this (https://www.martin-finke.de/articles/audio-plugins-018-polyblep-oscillator/).
const Oscillator = struct {
    const Self = @This();

    /// Each mode for the oscillator.
    const Mode = enum {
        sine,
        square,
        saw,
        triangle,
    };

    phase: f32 = 0.0,
    phase_increment: f32 = 0.0,
    frequency: f32 = 440.0,
    oscillator_mode: Mode = .sine,

    pub fn init(
        frequency: f32,
        oscillator_mode: Mode,
    ) Self {
        return .{
            .phase = 0.0,
            .frequency = frequency,
            .oscillator_mode = oscillator_mode,
        };
    }

    pub fn next(self: *Self) f32 {
        // Calculate the phase increment
        self.phase_increment = self.frequency * std.math.tau / 44100.0;

        // Make some temporary variables
        var value: f32 = 0.0;
        var t = self.phase / std.math.tau;

        // Calculate the oscillator value based on the mode
        // and add the poly BLEP correction if needed
        switch (self.oscillator_mode) {
            .sine => {
                value = std.math.sin(self.phase);
            },
            .square => {
                if (self.phase < std.math.pi) {
                    value = 1.0;
                } else {
                    value = -1.0;
                }
                value += self.polyBlep(t);
                value -= self.polyBlep(std.math.mod(f32, t + 0.5, 1.0) catch unreachable);
            },
            .saw => {
                value = (2 * self.phase / std.math.tau) - 1.0;
                value -= self.polyBlep(t);
            },
            .triangle => {
                value = -1.0 + (2.0 * self.phase / std.math.tau);
                value = 2.0 * (value - std.math.fabs(value) - 0.5);
                value -= self.polyBlep(t);
            },
        }

        // Increment the phase and wrap it around
        self.phase += self.phase_increment;
        if (self.phase >= std.math.tau) {
            self.phase -= std.math.tau;
        }

        return value;
    }

    /// Calculate the poly BLEP correction for the given phase.
    /// Based on this (https://www.martin-finke.de/articles/audio-plugins-018-polyblep-oscillator/).
    fn polyBlep(self: Self, _t: f32) f32 {
        var dt = self.phase_increment / std.math.tau;
        var t = _t;

        if (t < dt) {
            t /= dt;
            return t + t - t * t - 1.0;
        } else if (t > 1.0 - dt) {
            t = (t - 1.0) / dt;
            return t * t + t + t + 1.0;
        } else {
            return 0.0;
        }
    }
};

/// The synth for this project
const Synth = struct {
    const Self = @This();
    const synth_log = std.log.scoped(.synth);

    adsr: ADSR,
    oscillator: Oscillator,
    filter: IIRFilter,
    gain: f32,

    pub fn init(
        frequency: f32,
    ) Self {
        return .{
            .oscillator = Oscillator.init(frequency, .saw),
            .adsr = ADSR.init(44100.0),
            .filter = IIRFilter.init(.lowpass, 1000.0, 2.5, 1.0),
            .gain = 0.4,
        };
    }

    pub fn noteOn(self: *Self, note: i32) void {
        self.oscillator.frequency = midiNoteToPitch(note);
        self.adsr.noteOn();

        synth_log.debug("Note on: {} ({d})", .{ note, self.oscillator.frequency });
    }

    pub fn noteOff(self: *Self) void {
        self.adsr.noteOff();
    }

    pub fn next(self: *Self) f32 {
        const adsr = self.adsr.next();
        const cutoff = (1000.0 * adsr);
        self.filter.setFrequency(cutoff);
        return self.filter.next(self.oscillator.next() * 0.5) * self.gain;
    }
};

/// State of the audio system.
const State = struct {
    synth: Synth,

    pub fn init() State {
        return .{
            .synth = Synth.init(440.0),
        };
    }
};

var allocator: std.mem.Allocator = undefined;
var device: c.SDL_AudioDeviceID = 0;
var spec: c.SDL_AudioSpec = undefined;
var _state = State.init();
const audio_log = std.log.scoped(.audio);

pub fn init(_allocator: std.mem.Allocator) !void {
    allocator = _allocator;

    audio_log.debug("Initializing SDL audio subsystem", .{});
    if (c.SDL_Init(c.SDL_INIT_AUDIO) != 0) {
        return error.SDLInitFailed;
    }

    audio_log.debug("Opening audio device", .{});
    spec = c.SDL_AudioSpec{
        .freq = 44100,
        .format = c.AUDIO_F32,
        .channels = 2,
        .silence = 0,
        .samples = 128,
        .padding = 0,
        .size = 0,
        .callback = @ptrCast(&callback),
        .userdata = &_state,
    };
    device = c.SDL_OpenAudioDevice(
        null,
        0,
        &spec,
        null,
        0,
    );

    audio_log.debug("Starting audio device", .{});
    c.SDL_PauseAudioDevice(device, 0);

    audio_log.debug("Initialized audio", .{});
}

pub fn deinit() void {
    audio_log.debug("Pausing audio device", .{});
    c.SDL_PauseAudioDevice(device, 1);
    audio_log.debug("Closing audio device", .{});
    c.SDL_CloseAudioDevice(device);
}

fn callback(userdata: ?*anyopaque, stream: [*c]u8, len: c_int) void {
    // Get the audio system state.
    if (userdata == null) return;
    var state: *State = @ptrCast(@alignCast(userdata));

    // Get an aligned slice of the stream for f32 writing
    const bytes: []align(@alignOf(f32)) u8 = @alignCast(stream[0..@intCast(len)]);
    // Convert the slice to a slice of f32s
    var buffer = std.mem.bytesAsSlice(f32, bytes);

    // Write the audio samples to the stereo buffer

    while (buffer.len > 0) {
        var x = state.synth.next();

        // Clip the output to 1.0 for everyone's ears
        if (x >= 1.0) {
            x = 1.0;
        } else if (x <= -1.0) {
            x = -1.0;
        }

        buffer[0] = x;
        buffer[1] = x;
        buffer = buffer[2..];
    }
}

pub fn setFrequency(frequency: f32) void {
    _state.synth.oscillator.frequency = frequency;
}

pub fn noteOn(note: i32) void {
    _state.synth.noteOn(note);
}

pub fn noteOff() void {
    _state.synth.noteOff();
}

fn midiNoteToPitch(note: i32) f32 {
    return 440.0 * std.math.pow(f32, 2.0, @as(f32, @floatFromInt(note - 69)) / 12.0);
}
