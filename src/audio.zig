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

    state: ADSRState,
    envelope_value: f32,
    time_since_note_on: f32,
    time_since_note_off: f32,

    const ADSRState = enum { attack, decay, sustain, release, off };

    pub fn init(sample_rate: f32) ADSR {
        return ADSR{
            .attack_time = 0.001,
            .decay_time = 0.1,
            .sustain_level = 0.5,
            .release_time = 0.2,
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

    pub fn process(self: *ADSR) f32 {
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
/// TODO: This shit brokey...
pub const Filter = struct {
    const Self = @This();

    const Type = enum {
        lowpass,
        highpass,
        bandpass,
        notch,
        peak,
        lowshelf,
        highshelf,
    };

    type: Type = .lowpass,
    frequency: f32 = 1000.0,
    q: f32 = 1.0,
    gain: f32 = 0.0,

    a0: f32 = 0.0,
    a1: f32 = 0.0,
    a2: f32 = 0.0,
    b0: f32 = 1.0,
    b1: f32 = 0.0,
    b2: f32 = 0.0,

    x1: f32 = 0.0,
    x2: f32 = 0.0,
    y1: f32 = 0.0,
    y2: f32 = 0.0,

    pub fn init(
        _type: Type,
        frequency: f32,
        q: f32,
        gain: f32,
    ) Self {
        var self: Self = .{
            .type = _type,
            .frequency = frequency,
            .q = q,
            .gain = gain,
        };

        self.calculateCoefficients();

        return self;
    }

    pub fn next(self: *Self, input: f32) f32 {
        var output: f32 = 0.0;

        // Calculate the output
        output = self.a0 * input + self.a1 * self.x1 + self.a2 * self.x2 - self.b1 * self.y1 - self.b2 * self.y2;

        // Update the state
        self.x2 = self.x1;
        self.x1 = input;
        self.y2 = self.y1;
        self.y1 = output;

        return output;
    }

    fn calculateCoefficients(self: *Self) void {
        var omega: f32 = 0.0;
        var sin_omega: f32 = 0.0;
        var cos_omega: f32 = 0.0;
        var alpha: f32 = 0.0;

        omega = std.math.tau * self.frequency / 44100.0;
        sin_omega = std.math.sin(omega);
        cos_omega = std.math.cos(omega);
        alpha = sin_omega;

        switch (self.type) {
            .lowpass => {
                self.a0 = (1.0 - cos_omega) / 2.0;
                self.a1 = 1.0 - cos_omega;
                self.a2 = (1.0 - cos_omega) / 2.0;
                self.b1 = -2.0 * cos_omega;
                self.b2 = 1.0;
            },
            .highpass => {
                self.a0 = (1.0 + cos_omega) / 2.0;
                self.a1 = -(1.0 + cos_omega);
                self.a2 = (1.0 + cos_omega) / 2.0;
                self.b1 = -2.0 * cos_omega;
                self.b2 = 1.0;
            },
            .bandpass => {
                self.a0 = alpha;
                self.a1 = 0.0;
                self.a2 = -alpha;
                self.b1 = -2.0 * cos_omega;
                self.b2 = 1.0;
            },
            .notch => {
                self.a0 = 1.0;
                self.a1 = -2.0 * cos_omega;
                self.a2 = 1.0;
                self.b1 = -2.0 * cos_omega;
                self.b2 = 1.0;
            },
            .peak => {
                self.a0 = 1.0 + alpha * self.gain;
                self.a1 = -2.0 * cos_omega;
                self.a2 = 1.0 - alpha * self.gain;
                self.b1 = -2.0 * cos_omega;
                self.b2 = 1.0;
            },
            .lowshelf => {
                self.a0 = self.gain * ((self.gain + 1.0) - (self.gain - 1.0) * cos_omega + 2.0 * std.math.sqrt(self.gain) * alpha);
                self.a1 = 2.0 * self.gain * ((self.gain - 1.0) - (self.gain + 1.0) * cos_omega);
                self.a2 = self.gain * ((self.gain + 1.0) - (self.gain - 1.0) * cos_omega - 2.0 * std.math.sqrt(self.gain) * alpha);
                self.b1 = -2.0 * ((self.gain - 1.0) + (self.gain + 1.0) * cos_omega);
                self.b2 = (self.gain + 1.0) + (self.gain - 1.0) * cos_omega - 2.0 * std.math.sqrt(self.gain) * alpha;
            },
            .highshelf => {
                self.a0 = self.gain * ((self.gain + 1.0) + (self.gain - 1.0) * cos_omega + 2.0 * std.math.sqrt(self.gain) * alpha);
                self.a1 = -2.0 * self.gain * ((self.gain - 1.0) + (self.gain + 1.0) * cos_omega);
                self.a2 = self.gain * ((self.gain + 1.0) + (self.gain - 1.0) * cos_omega - 2.0 * std.math.sqrt(self.gain) * alpha);
                self.b1 = 2.0 * ((self.gain - 1.0) - (self.gain + 1.0) * cos_omega);
                self.b2 = (self.gain + 1.0) - (self.gain - 1.0) * cos_omega - 2.0 * std.math.sqrt(self.gain) * alpha;
            },
        }
    }

    fn reset(self: *Self) void {
        self.x1 = 0.0;
        self.x2 = 0.0;
        self.y1 = 0.0;
        self.y2 = 0.0;

        self.calculateCoefficients();
    }

    fn setFrequency(self: *Self, frequency: f32) void {
        self.frequency = frequency;
        self.calculateCoefficients();
    }

    fn setQ(self: *Self, q: f32) void {
        self.q = q;
        self.calculateCoefficients();
    }

    fn setGain(self: *Self, gain: f32) void {
        self.gain = gain;
    }

    fn setType(self: *Self, _type: Type) void {
        self.type = _type;
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

    adsr: ADSR,
    oscillator: Oscillator,
    filter: Filter,
    gain: f32,

    pub fn init(
        frequency: f32,
    ) Self {
        return .{
            .oscillator = Oscillator.init(frequency, .saw),
            .adsr = ADSR.init(44100.0),
            .filter = Filter.init(.lowpass, 1000.0, 1.0, 0.0),
            .gain = 1.0,
        };
    }

    pub fn noteOn(self: *Self, note: i32) void {
        self.oscillator.frequency = midiNoteToPitch(note);
        self.adsr.noteOn();

        std.log.debug("Note on: {} ({d})", .{ note, self.oscillator.frequency });
    }

    pub fn noteOff(self: *Self) void {
        self.adsr.noteOff();
    }

    pub fn next(self: *Self) f32 {
        const adsr = self.adsr.process();
        const cutoff = 1000.0 * adsr;
        self.filter.setFrequency(cutoff);
        return self.filter.next(self.oscillator.next()) * adsr * self.gain;
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

pub fn init(_allocator: std.mem.Allocator) !void {
    allocator = _allocator;

    std.log.debug("Initializing SDL audio subsystem", .{});
    if (c.SDL_Init(c.SDL_INIT_AUDIO) != 0) {
        return error.SDLInitFailed;
    }

    std.log.debug("Opening audio device", .{});
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

    std.log.debug("Starting audio device", .{});
    c.SDL_PauseAudioDevice(device, 0);

    std.log.debug("Initialized audio", .{});
}

pub fn deinit() void {
    std.log.debug("Pausing audio device", .{});
    c.SDL_PauseAudioDevice(device, 1);
    std.log.debug("Closing audio device", .{});
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
        const x = state.synth.next();
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
