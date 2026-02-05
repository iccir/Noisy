# Noisy Advanced Usage

## Table of Contents

- [Custom Noise Presets](#custom-noise-presets)
  - [File Format](#file-format)
  - [Auto Gain and Gain Structure](#auto-gain-and-gain-structure)
  - [Mono vs. Stereo Operation](#mono-vs-stereo-operation)
  - [Node Definitions](#node-definitions)
    - [DC Block Node](#dc-block-node)
    - [Gain Node](#gain-node)
    - [Generator Node](#generator-node)
    - [OnePole Node](#onepole-node)
    - [Pinking Node](#pinking-node)
    - [Split Node](#split-node)
    - [Stereo Node](#stereo-node)
    - [Zero Node](#zero-node)
- [Hidden Defaults](#hidden-defaults)


## Custom Noise Presets

Noisy includes the ability to create custom noise presets via JSON-formatted text files.

To access the presets folder, click on the "Show Presets Folder" button in the "Presets" pane of Settings. Noisy monitors this folder and automatically updates the "Presets" pane when new files are added.

Click the checkbox next to a preset's name to enable it. Only enabled presets will show up in the main Noisy window (or in the menu bar).

Several [example presets](https://github.com/iccir/Noisy/tree/main/Docs/Examples) are available.


### File Format

A Noisy preset should have a file extension of `.json`, be valid JSON or JSON5, and have a root level object which conforms to the `Preset` interface.

*All interface definitions in this document are specified in TypeScript syntax.*

```typescript
interface Preset {
    name?: string,
    program: Nodes[],
    autogain?: AutoGainSettings // See section below
}

// Specific Node interfaces are defined later
interface Node {
    type: string
}
```


Note that the first node of a `program` must either be a [generator node](#generator-node) or a [stereo node](#stereo-node). If a stereo node, the first node of the `left` and `right` arrays must be a generator node.


### Auto Gain and Gain Structure

Upon playback, Noisy first generates approximately 6 seconds of audio and applies [peak normalization](https://en.wikipedia.org/wiki/Audio_normalization) to -3 dBFS. This is called "Auto Gain" and may be controlled via the `"autogain"` key:

```typescript
interface AutoGainSettings {
    /*
        The target peak normalization level in dBFS
    */
    level?: number, // Default: -3
    
    /*
        If true, calculates and applies peak normalization
        to each channel separately. If false, the same
        amplication is applied to both channels.

        Has no effect for mono presets.
    */
    separate?: boolean // Default: false
}
```

As an optimization, Noisy does not scale the gain levels of individual nodes. Some nodes, such as a brownian generator followed by a DC block, will have significantly less loudness than a uniform generator.

In a simple preset with a single node list, Auto Gain will automatically compensate for this difference and levels will be similar. However, in a complex preset involving a [split node](#split-node) or [stereo node](#stereo-node), you will need to manually adjust gain of a branch with a [gain node](#gain-node).

### Mono vs. Stereo Operation

Noisy includes a "Stereo Field" setting which controls whether it runs in mono or stereo mode. Individual presets may also be mono or stereo, depending on the presence of a [stereo node](#stereo-node).

By default, both Noisy and the built-in presets run in mono mode. The root-level `program` is ran once on the left channel. The results are duplicated to the right channel.

When a mono preset is ran in stereo mode, a copy of the `program` nodes is made. One program generates the left channel's data and the other generates the right channel's data.

When a stereo preset is ran in mono mode, both the left and right programs generate data. The result is then mixed down to mono.

Note that a preset may only contain one [stereo node](#stereo-node). Having more than one stereo node will result in an error.


### Node Definitions

#### Biquads Node

```typescript
enum BiquadType {
    "peaking",
    "lowpass",
    "highpass",
    "bandpass",
    "lowshelf",
    "highshelf"
}

interface Biquad {
    type:      BiquadType,
    frequency: number,
    gain?:     number, // Default: 0.0
    Q?:        number  // Default: 0.7071
}

interface BiquadsNode extends Node {
    type: "biquads",
    biquads: Biquad[]
}
```

Applies a series of biquad filters using `vDSP_biquad()` to the input buffer.


#### DC Block Node

```typescript

interface DCBlockNode extends Node {
    type: "dcblock"
}
```

Implements a DC block via the following difference equation:

```text
y[n] = x[n] - x[n - 1] + 0.9997 * y[n - 1]
```

#### Gain Node

```
interface GainNode extends Node {
    type: "gain",
    gain: number // In dB
}
```

Adjusts the gain (in decibels) of the input buffer.


#### Generator Node

```typescript

enum GeneratorSubType {
    "uniform",
    "gaussian",
    "brownian"
}

interface GeneratorNode extends Node {
    type: "generator",
    subtype?: GeneratorSubType // Default: "uniform"
}
```

**Replaces** the contents of the input buffer with uniform, gaussian, or brownian noise. Generator nodes should only appear at the beginning of a node list.

Both `"uniform"` and `"gaussian"` use the [xoshiro256** PRNG algorithm](https://en.wikipedia.org/wiki/Xorshift) to generate random integers.

For `"uniform"`, the resulting 64-bit unsigned integer is split into four 16-bit signed integers.

For `"gaussian"`, the four 16-bit signed integers are averaged together. Due to the [Central Limit Theoreom](https://en.wikipedia.org/wiki/Central_limit_theorem), this should roughly approximate a gaussian distribution.

`"brownian"` uses a [random walk](https://en.wikipedia.org/wiki/Random_walk) to generate brownian noise. As the resulting noise will have a DC bias, it should be filtered by a [DC Block node](#dc-block-node) or a highpass filter.


#### OnePole Node

```typescript
enum OnePoleSubType {
    "lowpass",
    "highpass"
}

interface OnePoleNode extends Node {
    type: "onepole",
    subtype?: OnePoleSubType // Default: "lowpass"
    frequency: number
}
```

Applies a one-pole lowpass or highpass filter to the input buffer.


#### Pinking Node

```typescript
enum PinkingSubType {
    "pk3", // Paul Kellot's "refined" method
    "pke", // Paul Kellet's "economy" method
    "rbj"  // Robert Bristow-Johnson's 3-pole, 3-zero
}

interface PinkingNode extends Node {
    type: "pinking",
    subtype?: PinkingSubType // Default: "pk3"
}
```

Applies a pinking filter to the input buffer.


#### Split Node

```typescript
interface SplitNode extends Node {
    type: "split",
    programs: Node[][]
}
```

Duplicates the input buffer, runs `programs` on each duplicate, and sums the result.


#### Stereo Node

```typescript
interface StereoNode extends Node {
    type: "stereo",
    left:  Node[],
    right: Node[]
}
```

If the first node of a `program`: specifies the two node arrays used to generate left and right data. Each array must start with a [generator node](#generator-node).

If a subsequent node in a `program`:

1. Copies the input buffer twice.
2. Runs the `left` node array on the first buffer and sends it to the left channel.
3. Runs the `right` node array on the second buffer and sends it to the right channel.

There may only be one stereo node.


#### Zero Node

```typescript
interface ZeroNode extends Node {
    type: "zero"
}
```

**Replaces** the contents of the input buffer with zeros. This node type is only useful when debugging split nodes.


## Hidden Defaults

Noisy includes a few hidden defaults which may be modified in Terminal via the `defaults` command.

#### Use Now Playing SPI

`defaults write com.iccir.Noisy useNowPlayingSPI -bool YES`

Historically, applications have been able to use the MediaRemote framework to query if another app is playing media. This corresponds to macOS's "Now Playing" feature.

Unfortunately, Apple disabled third-party access to Now Playing starting in macOS Sequoia 15.4 and refuses to offer a replacement. Hence, Noisy will hide the "Mute when Now Playing is active" checkbox in Settings when running on Sequoia 15.4 or higher.

If you have manually patched `mediaremoted` or are running Noisy with Apple-private entitlements, you can set `useNowPlayingSPI` to `YES` to force the Now Playing checkbox to reappear.

This setting has no effect on macOS Sequoia 15.3 or earlier.


#### Play Fade Duration

`defaults write com.iccir.Noisy playFadeDuration -float 0.1`

Controls the fade duration when starting playback. Defaults to 0.1 seconds (100ms).

#### Pause Fade Duration
  
`defaults write com.iccir.Noisy pauseFadeDuration -float 0.15`

Controls the fade duration when starting playback. Defaults to 0.15 seconds (150ms).


#### Mute Fade Duration

`defaults write com.iccir.Noisy muteFadeDuration -float 1.0`

Controls the fade duration when applying or removing Auto Mute. Defaults to 1 second.
