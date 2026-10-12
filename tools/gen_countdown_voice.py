"""SuuUI's countdown voice: a Piper voice model (onnx) speaking one to ten and
"pull", run directly with onnxruntime from hand-written IPA phonemes (the
same espeak-ng en-us phonemes Piper would produce; this macOS wheel's espeak
bridge is broken), trimmed, normalised and written as Ogg Vorbis.

    python3 -m venv env && env/bin/pip install onnxruntime soundfile numpy
    # models: https://huggingface.co/rhasspy/piper-voices (the .onnx and its
    # .onnx.json): en/en_US/ljspeech/high (Female), en/en_US/norman/medium (Male)
    env/bin/python -I tools/gen_countdown_voice.py en_US-ljspeech-high.onnx Media/Sounds/Countdown/Female 1.0
    env/bin/python -I tools/gen_countdown_voice.py en_US-norman-medium.onnx Media/Sounds/Countdown/Male 1.0

Both voices were trained from scratch on public-domain recordings (LJ Speech,
LibriVox); see Media/Sounds/Countdown/license.txt. Listen to the results:
sampling is random, and a take can come out wrong (run it again).
"""
import json
import sys

import numpy as np
import onnxruntime as ort
import soundfile as sf

# espeak-ng en-us IPA, with stress marks, as Piper's training used them
WORDS = {
    1: "wˈʌn", 2: "tˈuː", 3: "θɹˈiː", 4: "fˈoːɹ", 5: "fˈaɪv", 6: "sˈɪks", 7: "sˈɛvən",
    8: "ˈeɪt", 9: "nˈaɪn", 10: "tˈɛn", "pull": "pˈʊl",
}


def phoneme_ids(phonemes, id_map, ending):
    ids = list(id_map["^"])
    for p in phonemes + ending:
        if p not in id_map:
            raise KeyError(f"phoneme {p!r} not in the model")
        ids.extend(id_map[p])
        ids.extend(id_map["_"])
    ids.extend(id_map["$"])
    return ids


def trim(data, rate, threshold=0.03, gap=0.12, pad=0.03):
    """The first spoken segment only: from the first loud 10 ms to the first
    pause longer than `gap` (single words can trail off into babble)."""
    win = int(0.01 * rate)
    env = [float(np.sqrt(np.mean(data[i:i + win] ** 2))) for i in range(0, len(data), win)]
    loud = [i for i, e in enumerate(env) if e > threshold]
    if not loud:
        return data
    first = loud[0]
    last = first
    quiet = 0
    for i in range(first, len(env)):
        if env[i] > threshold:
            last, quiet = i, 0
        else:
            quiet += 1
            if quiet * 0.01 >= gap:
                break
    start = max(0, first * win - int(pad * rate))
    end = min(len(data), (last + 1) * win + int(pad * 2 * rate))
    out = data[start:end].copy()
    fade = int(0.008 * rate)
    out[:fade] *= np.linspace(0, 1, fade)
    out[-fade:] *= np.linspace(1, 0, fade)
    return out


def main():
    model, out = sys.argv[1], sys.argv[2]
    length_scale = float(sys.argv[3]) if len(sys.argv) > 3 else 0.9
    with open(model + ".json", encoding="utf-8") as f:
        config = json.load(f)
    id_map = config["phoneme_id_map"]
    rate = config["audio"]["sample_rate"]
    inference = config.get("inference", {})
    # steadier than the defaults (0.667, 0.8): single words go astray otherwise
    noise, noise_w = 0.4, 0.5
    session = ort.InferenceSession(model, providers=["CPUExecutionProvider"])
    for key, phonemes in WORDS.items():
        ids = phoneme_ids(phonemes, id_map, "!" if key == "pull" else ".")
        inputs = {
            "input": np.array([ids], dtype=np.int64),
            "input_lengths": np.array([len(ids)], dtype=np.int64),
            "scales": np.array([noise, length_scale, noise_w], dtype=np.float32),
        }
        if any(i.name == "sid" for i in session.get_inputs()):
            inputs["sid"] = np.array([0], dtype=np.int64)
        # sampling is random: a few takes, the first that sounds like one
        # word (a plausible length); else the shortest
        takes = []
        for _ in range(12):
            take = trim(session.run(None, inputs)[0].squeeze().astype(np.float32), rate)
            takes.append(take)
            if 0.2 <= len(take) / rate <= 0.75:
                break
        audio = min(takes, key=lambda t: abs(len(t) / rate - 0.45)) if not (0.2 <= len(takes[-1]) / rate <= 0.75) else takes[-1]
        peak = float(np.max(np.abs(audio))) or 1.0
        audio = audio / peak * 0.89  # about -1 dBFS
        path = f"{out}/{key}.ogg"
        sf.write(path, audio, rate, format="OGG", subtype="VORBIS")
        print(path, f"{len(audio) / rate:.2f}s")


if __name__ == "__main__":
    main()
