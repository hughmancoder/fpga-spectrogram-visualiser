#!/usr/bin/env python3
"""
Generate Q1.15 signed fixed-point Twiddle Factor ROM tables for a Radix-2 FFT.

For an N-point FFT (default N = 64), the twiddle factors are:
    W_N^k = cos(2 * pi * k / N) - j * sin(2 * pi * k / N)   for k = 0 .. (N/2 - 1)

Values are scaled to signed 16-bit Q1.15 format:
    +1.0 -> +32767 (0x7FFF)
    -1.0 -> -32767 (0x8001)

Outputs:
    src/rom/twiddle_cos.hex
    src/rom/twiddle_sin.hex
"""

import argparse
import math
from pathlib import Path


def to_q15_hex(val: float) -> tuple[int, str]:
    """Convert float in [-1.0, +1.0] to signed 16-bit Q1.15 integer and 4-char hex."""
    # every bit here is multiplied by 2^15 and stored as a 16 bit signed integer
    q15 = int(round(val * 32767.0))
    q15 = max(-32768, min(32767, q15))
    hex_str = f"{q15 & 0xFFFF:04x}"
    return q15, hex_str


def generate_twiddles(fft_size: int, out_dir: Path) -> None:
    half_n = fft_size // 2
    cos_path = out_dir / "twiddle_cos.hex"
    sin_path = out_dir / "twiddle_sin.hex"

    with open(cos_path, "w", encoding="utf-8") as f_cos, open(
        sin_path, "w", encoding="utf-8"
    ) as f_sin:
        f_cos.write(f"// Q1.15 cos(2*pi*k/{fft_size}) for k = 0..{half_n - 1}\n")
        f_sin.write(f"// Q1.15 -sin(2*pi*k/{fft_size}) for k = 0..{half_n - 1}\n")

        for k in range(half_n):
            angle = 2.0 * math.pi * k / fft_size
            cos_val = math.cos(angle)
            sin_val = -math.sin(angle)

            cos_q15, cos_hex = to_q15_hex(cos_val)
            sin_q15, sin_hex = to_q15_hex(sin_val)

            f_cos.write(f"{cos_hex} // k={k:2d}: {cos_val:+.6f} ({cos_q15:+6d})\n")
            f_sin.write(f"{sin_hex} // k={k:2d}: {sin_val:+.6f} ({sin_q15:+6d})\n")

    print(f"Generated {half_n} twiddle factors (N={fft_size}):")
    print(f"  -> {cos_path}")
    print(f"  -> {sin_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate Q1.15 FFT twiddle factor .hex files.")
    parser.add_argument(
        "-n", "--fft-size", type=int, default=64, help="FFT size N (power of 2, default: 64)"
    )
    args = parser.parse_args()

    rom_dir = Path(__file__).resolve().parent
    generate_twiddles(args.fft_size, rom_dir)

