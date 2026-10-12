"""SuuUI's countdown voice: Kokoro-82M (hexgrad, Apache-2.0 weights; the
kokoro-onnx export) run directly with onnxruntime from hand-written misaki
phonemes (American English, as Kokoro was trained; espeak isn't needed for
eleven words), at its native 24 kHz: the first spoken segment kept,
normalised to -1 dBFS, Ogg Vorbis at its highest quality.

    python -m venv env && env/bin/pip install onnxruntime soundfile numpy
    # kokoro-v1.0.onnx and voices-v1.0.bin: github.com/thewh1teagle/kokoro-onnx
    # releases (model-files-v1.1); config.json: huggingface.co/hexgrad/Kokoro-82M
    env/bin/python -I tools/gen_countdown_voice.py <model dir> <voice> <out dir>
    #   voices used: af_heart (Female), am_michael (Male)
"""
import json
import sys

import numpy as np
import onnxruntime as ort
import soundfile as sf

RATE = 24000
# misaki American phonemes (A = eɪ, I = aɪ)
WORDS = {
    1: "wˈʌn.", 2: "tˈu.", 3: "θɹˈi.", 4: "fˈɔɹ.", 5: "fˈIv.", 6: "sˈɪks.", 7: "sˈɛvən.",
    8: "ˈAt.", 9: "nˈIn.", 10: "tˈɛn.", "pull": "pˈʊl!",
}


def trim(data, rate, gap=0.15, pad=0.03):
    """From the first loud 10 ms to the first pause longer than `gap`
    (threshold relative to the take's own peak)."""
    win = int(0.01 * rate)
    env = np.array([np.sqrt(np.mean(data[i:i + win] ** 2)) for i in range(0, len(data), win)])
    threshold = env.max() * 0.06
    loud = np.where(env > threshold)[0]
    if len(loud) == 0:
        return data
    first, last, quiet = loud[0], loud[0], 0
    for i in range(first, len(env)):
        if env[i] > threshold:
            last, quiet = i, 0
        else:
            quiet += 1
            if quiet * 0.01 >= gap:
                break
    start = max(0, first * win - int(pad * rate))
    end = min(len(data), (last + 1) * win + int(pad * 3 * rate))
    out = data[start:end].astype(np.float32).copy()
    fade = int(0.006 * rate)
    out[:fade] *= np.linspace(0, 1, fade)
    out[-fade * 2:] *= np.linspace(1, 0, fade * 2)
    return out


def main():
    folder, voice, out = sys.argv[1:4]
    vocab = json.load(open(f"{folder}/config.json", encoding="utf-8"))["vocab"]
    styles = np.load(f"{folder}/voices-v1.0.bin")[voice]
    session = ort.InferenceSession(f"{folder}/kokoro-v1.0.onnx", providers=["CPUExecutionProvider"])
    for key, phonemes in WORDS.items():
        ids = [vocab[p] for p in phonemes]
        tokens = np.array([[0, *ids, 0]], dtype=np.int64)
        style = styles[len(ids)].astype(np.float32)
        audio = session.run(None, {"input_ids": tokens, "style": style, "speed": np.array([1.0], dtype=np.float32)})[0]
        audio = trim(np.asarray(audio, dtype=np.float32).squeeze(), RATE)
        audio = audio / (float(np.max(np.abs(audio))) or 1.0) * 0.89
        path = f"{out}/{key}.ogg"
        sf.write(path, audio, RATE, format="OGG", subtype="VORBIS", compression_level=0.0)
        print(path, f"{len(audio) / RATE:.2f}s")


if __name__ == "__main__":
    main()
