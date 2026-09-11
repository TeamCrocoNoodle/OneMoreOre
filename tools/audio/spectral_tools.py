"""Small standard-library FFT/STFT helpers for offline audio editing.

STFT frames contain n_fft // 2 + 1 complex bins, ordered from DC to Nyquist.
Both transforms use a periodic Hann window and hop samples between frames.
The STFT centers its frames with reflected padding; ISTFT removes that padding
and divides by the overlap sum of squared windows to restore the exact length.
No phase reconstruction, audio filtering, or source separation is performed.
"""

from functools import lru_cache
import math


def _validate_fft_size(size):
    if not isinstance(size, int) or size < 1 or size & (size - 1):
        raise ValueError("FFT size must be a positive power of two")


@lru_cache(maxsize=16)
def _fft_plan(size, inverse):
    _validate_fft_size(size)
    bits = size.bit_length() - 1
    reverse = []
    for index in range(size):
        value, reversed_value = index, 0
        for _ in range(bits):
            reversed_value = (reversed_value << 1) | (value & 1)
            value >>= 1
        reverse.append(reversed_value)
    sign = 1.0 if inverse else -1.0
    stages = []
    span = 2
    while span <= size:
        angle = sign * math.tau / span
        twiddles = tuple(complex(math.cos(angle * index), math.sin(angle * index))
                         for index in range(span // 2))
        stages.append((span, twiddles))
        span *= 2
    return tuple(reverse), tuple(stages)


def fft(values, inverse=False):
    """Return a radix-2 complex FFT; inverse includes the 1/N normalization.

    The input is copied and is never changed. Its length must be a nonzero
    power of two. Bit-reversal indices and stage twiddles are cached by size.
    """
    values = [complex(value) for value in values]
    size = len(values)
    reverse, stages = _fft_plan(size, bool(inverse))
    result = [values[index] for index in reverse]
    for span, twiddles in stages:
        half = span // 2
        for start in range(0, size, span):
            for offset, twiddle in enumerate(twiddles):
                left = start + offset
                right = left + half
                even = result[left]
                odd = result[right] * twiddle
                result[left] = even + odd
                result[right] = even - odd
    if inverse:
        scale = 1.0 / size
        result = [value * scale for value in result]
    return result


@lru_cache(maxsize=8)
def _hann(size):
    return tuple(0.5 - 0.5 * math.cos(math.tau * index / size)
                 for index in range(size))


def _validate_stft(n_fft, hop):
    _validate_fft_size(n_fft)
    if n_fft < 2:
        raise ValueError("STFT n_fft must be at least two")
    if not isinstance(hop, int) or not 1 <= hop <= n_fft // 2:
        raise ValueError("STFT hop must be between one and n_fft // 2")


def _reflect_index(index, length):
    if length == 1:
        return 0
    period = 2 * (length - 1)
    index %= period
    return index if index < length else period - index


def stft(samples, n_fft=2048, hop=256):
    """Return frame-major, one-sided spectra of real samples.

    There are 1 + len(samples) // hop centered frames for nonempty input.
    Reflection excludes the endpoint itself, including when padding is longer
    than a short input. A single input sample uses constant padding. Empty
    input returns an empty list. Process stereo channels separately and apply
    a shared mask when their stereo relationship should remain unchanged.
    """
    _validate_stft(n_fft, hop)
    samples = [float(value) for value in samples]
    length = len(samples)
    if not length:
        return []
    padding = n_fft // 2
    padded = [samples[_reflect_index(index, length)]
              for index in range(-padding, length + padding)]
    window = _hann(n_fft)
    spectra = []
    for start in range(0, len(padded) - n_fft + 1, hop):
        frame = [padded[start + index] * window[index] for index in range(n_fft)]
        spectra.append(fft(frame)[:padding + 1])
    return spectra


def istft(spectra, n_samples, n_fft=2048, hop=256):
    """Restore real samples from matching one-sided STFT frames.

    n_samples is the original unpadded sample count. Each spectrum must have
    n_fft // 2 + 1 bins. DC and Nyquist are treated as real values, as required
    for real audio. Missing coverage is rejected instead of silently returning
    a truncated or zero-padded waveform.
    """
    _validate_stft(n_fft, hop)
    if not isinstance(n_samples, int) or n_samples < 0:
        raise ValueError("n_samples must be a nonnegative integer")
    if n_samples == 0:
        return []
    if not spectra:
        raise ValueError("Nonempty audio requires STFT frames")
    padding = n_fft // 2
    output_length = n_fft + hop * (len(spectra) - 1)
    if padding + n_samples > output_length:
        raise ValueError("Not enough STFT frames for n_samples")
    output = [0.0] * output_length
    weights = [0.0] * output_length
    window = _hann(n_fft)
    window_squared = tuple(value * value for value in window)
    for frame_index, spectrum in enumerate(spectra):
        if len(spectrum) != padding + 1:
            raise ValueError("Each STFT frame must have n_fft // 2 + 1 bins")
        positive = [complex(value) for value in spectrum]
        positive[0] = complex(positive[0].real, 0.0)
        positive[-1] = complex(positive[-1].real, 0.0)
        full = positive + [value.conjugate() for value in positive[-2:0:-1]]
        frame = fft(full, inverse=True)
        start = frame_index * hop
        for index in range(n_fft):
            output[start + index] += frame[index].real * window[index]
            weights[start + index] += window_squared[index]
    restored = []
    for index in range(padding, padding + n_samples):
        if weights[index] <= 1e-15:
            raise ValueError("STFT frames leave an uncovered output sample")
        restored.append(output[index] / weights[index])
    return restored
