#!/usr/bin/env python3
"""Sintetizza i suoni dell'interfaccia di SESTRIA e il tema del menu (liuto, bordone e tamburo), tutto originale.
Uso: python3 tools/make_ui_audio.py   → scrive assets/audio/ui/*.wav (22050 Hz, mono, 16 bit)."""
import math, os, random, struct, wave

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "ui")
os.makedirs(OUT, exist_ok=True)

def write(name, samples, gain=0.9):
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = 32767 * gain / peak if peak > 1.0 else 32767 * gain
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(SR)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * (scale / 32767)))* 32767)) for s in samples))

def env(i, n, attack=0.004, power=3.0):
    t = i / SR
    a = min(1.0, t / attack) if attack > 0 else 1.0
    return a * (1.0 - i / n) ** power

def noise(n, seed):
    r = random.Random(seed)
    return [r.uniform(-1, 1) for _ in range(n)]

def lowpass(x, k):
    y, out = 0.0, []
    for s in x:
        y += k * (s - y); out.append(y)
    return out

def highpass(x, k):
    lp = lowpass(x, k)
    return [a - b for a, b in zip(x, lp)]

def knock(freq, ms, drop=0.55, tick=0.5, seed=1):
    n = int(SR * ms / 1000)
    r = random.Random(seed)
    out, phase = [], 0.0
    for i in range(n):
        f = freq * (1.0 - drop * i / n)
        phase += 2 * math.pi * f / SR
        body = math.sin(phase) * env(i, n, 0.001, 2.6)
        click = r.uniform(-1, 1) * max(0.0, 1.0 - i / (SR * 0.012)) * tick
        out.append(body + click)
    return out

def bell(freqs, ms, seed=2):
    n = int(SR * ms / 1000)
    out = [0.0] * n
    for k, f in enumerate(freqs):
        amp = 1.0 / (1 + k * 0.7)
        for i in range(n):
            out[i] += math.sin(2 * math.pi * f * i / SR) * amp * env(i, n, 0.002, 2.2 + k * 0.5)
    return out

def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, s in enumerate(t):
            out[i] += s
    return out

def sfx():
    write("ui_hover", [s * 0.5 for s in mix(knock(620, 45, 0.2, 0.9, 3), [0.0] * 200)], 0.45)
    write("ui_click", knock(190, 110, 0.5, 0.7, 4), 0.85)
    write("ui_back", knock(140, 130, 0.55, 0.6, 5), 0.8)
    rustle = highpass(lowpass(noise(int(SR * 0.32), 7), 0.35), 0.08)
    n = len(rustle)
    write("ui_open", [s * (math.sin(math.pi * i / n) ** 0.7) * (0.6 + 0.4 * math.sin(i * 0.05)) for i, s in enumerate(rustle)], 0.7)
    write("ui_confirm", mix(knock(210, 90, 0.5, 0.5, 8), [0.0] * 800 + bell([880, 1318, 1760], 700)), 0.8)
    write("ui_error", mix(knock(95, 220, 0.4, 0.3, 9), [s * 0.2 for s in lowpass(noise(int(SR * 0.12), 10), 0.2)]), 0.8)
    write("ui_seal", mix(knock(68, 380, 0.45, 0.8, 11), [0.0] * 1200 + knock(300, 120, 0.5, 0.4, 12)), 0.9)
    write("ui_tab", mix(knock(260, 80, 0.4, 0.6, 13), [0.0] * 400 + bell([1046], 200)), 0.7)

# ---- Tema del menu ----
def pluck(freq, dur, vel=1.0, seed=0, damp=0.996, bright=0.5):
    n = int(SR * dur)
    period = max(2, int(SR / freq))
    r = random.Random(seed)
    buf = [r.uniform(-1, 1) * bright for _ in range(period)]
    # il liuto ha una cassa calda: filtra un poco l'eccitazione
    for i in range(1, period):
        buf[i] = 0.5 * buf[i] + 0.5 * buf[i - 1]
    out = []
    idx = 0
    for i in range(n):
        s = buf[idx]
        nxt = buf[(idx + 1) % period]
        buf[idx] = damp * 0.5 * (s + nxt)
        out.append(s * vel)
        idx = (idx + 1) % period
    fade = int(SR * 0.05)
    for i in range(min(fade, n)):
        out[n - 1 - i] *= i / fade
    return out

def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)

def drum(ms, freq=110, seed=1):
    n = int(SR * ms / 1000)
    r = random.Random(seed)
    out, phase = [], 0.0
    lp = 0.0
    for i in range(n):
        f = freq * (1 - 0.5 * i / n)
        phase += 2 * math.pi * f / SR
        lp += 0.15 * (r.uniform(-1, 1) - lp)
        out.append((math.sin(phase) * 0.9 + lp * 0.5) * env(i, n, 0.002, 3.0))
    return out

def theme():
    bpm = 66
    beat = 60.0 / bpm
    bars = 16
    total = int(SR * beat * 4 * bars)
    tail = int(SR * 3.5)
    track = [0.0] * (total + tail)
    def add(samples, start_beat, gain):
        s = int(start_beat * beat * SR)
        for i, v in enumerate(samples):
            j = s + i
            if j < len(track):
                track[j] += v * gain
    # accordi in re dorico: Dm C Dm Am | Dm C G Dm (ripetuti)
    chords = [(50, [57, 62, 65]), (48, [55, 60, 64]), (50, [57, 62, 65]), (45, [52, 57, 60]),
              (50, [57, 62, 65]), (48, [55, 60, 64]), (43, [50, 55, 59]), (50, [57, 62, 65])]
    pattern = [0, 1, 2, 1, 2, 1, 2, 1]      # ottavi: arpeggio fingerpicking
    seed = 1
    for bar in range(bars):
        bass, notes = chords[bar % 8]
        add(pluck(midi(bass), 3.2, 1.0, seed, 0.9975, 0.9), bar * 4, 0.55); seed += 1
        for step, k in enumerate(pattern):
            add(pluck(midi(notes[k]), 1.6, 0.8, seed, 0.9965, 0.5), bar * 4 + step * 0.5, 0.28); seed += 1
    # melodia (beat, midi, durata): sulla scala re dorica
    mel = [(0, 69, 2), (2, 72, 1), (3, 71, 1), (4, 69, 3), (7, 67, 1), (8, 65, 2), (10, 67, 1), (11, 69, 1),
           (12, 67, 3), (15, 64, 1), (16, 62, 2), (18, 65, 1), (19, 69, 1), (20, 72, 2), (22, 71, 1), (23, 69, 1),
           (24, 69, 2), (26, 67, 1), (27, 65, 1), (28, 62, 4)]
    for rep in (0, 32):
        for beat0, note, dur in mel:
            add(pluck(midi(note), 2.8, 1.0, seed, 0.998, 0.35), rep + beat0, 0.42); seed += 1
    # bordone: re e la, lento
    n = len(track)
    for i in range(total):
        t = i / SR
        swell = 0.5 + 0.5 * math.sin(2 * math.pi * t / (beat * 16))
        track[i] += (math.sin(2 * math.pi * 73.42 * t) * 0.6 + math.sin(2 * math.pi * 110.0 * t * 1.002) * 0.3) * (0.05 + 0.04 * swell)
    # tamburo a cornice nelle battute 5-8 e 13-16
    for bar in list(range(4, 8)) + list(range(12, 16)):
        add(drum(380, 105, bar), bar * 4, 0.34)
        add(drum(300, 95, bar + 50), bar * 4 + 2, 0.22)
        add(drum(200, 130, bar + 90), bar * 4 + 3.5, 0.14)
    # riverbero a pettine
    wet = [0.0] * len(track)
    for delay_ms, fb in ((41, 0.42), (53, 0.38), (67, 0.34), (89, 0.3)):
        d = int(SR * delay_ms / 1000)
        for i in range(d, len(track)):
            wet[i] += (track[i - d] + wet[i - d] * fb) * 0.22
    out = [t + w for t, w in zip(track, wet)]
    # loop senza stacchi: la coda si somma all'inizio
    for i in range(tail):
        out[i] += out[total + i]
    out = out[:total]
    fade = int(SR * 0.03)
    for i in range(fade):
        out[i] *= i / fade
    return out

if __name__ == "__main__":
    sfx()
    write("menu_theme", theme(), 0.8)
    print("AUDIO INTERFACCIA | suoni e tema scritti in", os.path.abspath(OUT))
