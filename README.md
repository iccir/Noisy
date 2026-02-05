# Noisy

[Noisy](https://www.ricciadams.com/projects/noisy) is a macOS noise generator with a simple interface yet powerful feature set.

See [Noisy Advanced Usage]() to learn about custom noise presets or hidden defaults.


## Philosophy

Audio programming is hard. macOS audio programming is harder
(usually due to sparse documentation). This repository is publicly-viewable
in the hopes that its source code can help others.

This repository is closed to outside contributions. **Please do not submit pull requests**.

If you are struggling with an audio or DSP concept, you can
contact me via my [contact form](https://www.ricciadams.com) and
I can try to point you in the right direction.


## History

Around 2001, a company called Blackhole Media released Noise for Mac OS X. It was a beloved [pink noise]() generator which I used for many years. Unfortunately, it didn't survive Apple's transition from PowerPC to Intel.

I decided to fix this in 2008 by creating Noisy. As I worked for Apple at the time, I released it anonymously. I maintained it until 2010 when a hard drive failure destroyed my login credentials to the anonymous account.

In 2025, unable to find a lightweight and efficient noise generator, I decided to recreate Noisy.

## Acknowledgements

- Noisy's icon is based on [The Great Wave off Kanagawa](https://en.wikipedia.org/wiki/The_Great_Wave_off_Kanagawa) by Katsushika Hokusai.
- Noisy uses [xoshiro256**](https://prng.di.unimi.it) by Sebastiano Vigna and David Blackman for random number generation.
- Pink Noise is generated using Paul Kellet "pk3" filter as posted to the Music-DSP mailing list on 1999-10-17.
- Brown Noise is generated using a [random walk algorithm](https://en.wikipedia.org/wiki/Random_walk). Thanks to [Douglas McCausland](https://www.douglas-mccausland.net) for sharing his Max patch (based on code from Luigi Castelli).


## License

I only care about proper attribution in source code. While attribution in binary form is welcomed, it is not necessary.

Hence, unless otherwise noted, all files in this project are licensed under both the [MIT License](https://github.com/iccir/Noisy/blob/main/LICENSE) OR the [1-clause BSD License](https://opensource.org/license/bsd-1-clause). You may choose either license.

`SPDX-License-Identifier: MIT OR BSD-1-Clause`
