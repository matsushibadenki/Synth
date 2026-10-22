"""Optional comparison: python3 Tests/CompareSyncSpectrum.py before.sync.wav after.sync.wav.
Requires numpy and scipy. Run AnalogDemo.swift against each DSP revision first.
This measures off-harmonic power, including modulation sidebands; it is not a
measurement of hardware fidelity or a general bound on aliasing in every patch.
"""
import sys
import numpy as np
from scipy.io import wavfile

for path in sys.argv[1:]:
    sample_rate, signal = wavfile.read(path)
    count = 131072
    assert signal.ndim == 1 and len(signal) >= count and sample_rate == 48000
    signal = signal[-count:].astype(np.float64)
    power = abs(np.fft.rfft(signal * np.hanning(count))) ** 2
    frequency = np.fft.rfftfreq(count, 1 / sample_rate)
    candidates = np.where((frequency > 1550) & (frequency < 1590))[0]
    fundamental = frequency[candidates[np.argmax(power[candidates])]]
    harmonics = np.zeros(len(frequency), dtype=bool)
    for harmonic in range(1, int(20000 / fundamental) + 1):
        harmonics |= abs(frequency - harmonic * fundamental) < 20
    band = (frequency > 100) & (frequency < 20000)
    ratio = power[band & ~harmonics].sum() / power[band & harmonics].sum()
    print(f"{path}: fundamental {fundamental:.3f} Hz, off-harmonic/harmonic {10*np.log10(ratio):.2f} dB")
