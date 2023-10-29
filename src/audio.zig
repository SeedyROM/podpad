const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_audio.h");
});

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
            .attack_time = 0.0,
            .decay_time = 0.1,
            .sustain_level = 0.5,
            .release_time = 0.8,
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

const SineOsc = struct {
    phase: f32 = 0.0,
    frequency: f32 = 440.0,

    pub fn init(frequency: f32) SineOsc {
        return .{
            .phase = 0.0,
            .frequency = frequency,
        };
    }

    pub fn next(self: *SineOsc) f32 {
        defer self.phase += self.frequency / 44100.0;
        return std.math.sin(self.phase * 2.0 * std.math.pi);
    }
};

const SineSynth = struct {
    oscillator: SineOsc,
    adsr: ADSR,
    gain: f32,

    pub fn init(
        frequency: f32,
    ) SineSynth {
        return .{
            .oscillator = SineOsc{
                .phase = 0.0,
                .frequency = frequency,
            },
            .adsr = ADSR.init(44100.0),
            .gain = 0.6,
        };
    }

    pub fn noteOn(self: *SineSynth) void {
        self.adsr.noteOn();
    }

    pub fn noteOff(self: *SineSynth) void {
        self.adsr.noteOff();
    }

    pub fn next(self: *SineSynth) f32 {
        return self.oscillator.next() * self.adsr.process() * self.gain;
    }
};

const State = struct {
    synth: SineSynth,

    pub fn init() State {
        return .{
            .synth = SineSynth.init(440.0),
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
        .samples = 512,
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

    // Write the audio samples to the buffer
    for (0..buffer.len) |i| {
        const x = state.synth.next();
        buffer[i] = x;
    }
}

pub fn setFrequency(frequency: f32) void {
    _state.synth.oscillator.frequency = frequency;
}

pub fn noteOn() void {
    _state.synth.noteOn();
}

pub fn noteOff() void {
    _state.synth.noteOff();
}
