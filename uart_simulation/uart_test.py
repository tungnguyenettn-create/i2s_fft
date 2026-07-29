#!/usr/bin/env python3
"""
UART test harness for axi_uart_rx / axi_uart_tx on the Tang Nano 9K.

Sends 16-bit words (as two bytes, high byte first -- matching the
ASSEMBLE state's {audio_data[7:0], byte_data} packing) and checks
whatever comes back matches what was sent, the same idea as the
uart_sim.v scoreboard, just against real hardware instead of simulation.

Usage:
    python3 uart_test.py --port /dev/ttyUSB1 --baud 115200 --count 255
"""

import argparse
import sys
import time

try:
    import serial
except ImportError:
    print("pyserial not found. Install with: pip install pyserial", file=sys.stderr)
    sys.exit(1)


def build_test_words(count):
    """Same sequence as uart_sim.v's scoreboard: word n = (2n << 8) | (2n+1)."""
    words = []
    for n in range(count):
        hi = (2 * n) & 0xFF
        lo = (2 * n + 1) & 0xFF
        words.append((hi << 8) | lo)
    return words


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", required=True, help="e.g. /dev/ttyUSB1 or COM5")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--count", type=int, default=255, help="number of 16-bit words to send")
    ap.add_argument("--gap", type=float, default=0.005, help="seconds between words (avoid flooding a stalled receiver)")
    ap.add_argument("--timeout", type=float, default=2.0, help="read timeout per word, seconds")
    args = ap.parse_args()

    words = build_test_words(args.count)

    print(f"Opening {args.port} @ {args.baud} baud...")
    with serial.Serial(args.port, args.baud, timeout=args.timeout) as ser:
        ser.reset_input_buffer()
        ser.reset_output_buffer()

        mismatches = 0
        received = 0

        for n, word in enumerate(words):
            hi = (word >> 8) & 0xFF
            lo = word & 0xFF

            # Send high byte then low byte, matching ASSEMBLE's expected order.
            ser.write(bytes([hi, lo]))
            ser.flush()

            # Read back whatever the loopback/pipeline sends out.
            rx_bytes = ser.read(2)
            if len(rx_bytes) < 2:
                print(f"[TIMEOUT] word {n}: sent {word:04x}, got no reply "
                      f"(only {len(rx_bytes)} byte(s))")
                continue

            rx_word = (rx_bytes[0] << 8) | rx_bytes[1]
            received += 1

            if rx_word != word:
                mismatches += 1
                print(f"[MISMATCH] word {n}: sent {word:04x}, got {rx_word:04x}")
            else:
                print(f"[OK]       word {n}: {word:04x}")

            time.sleep(args.gap)

        print()
        print(f"Sent {len(words)} words, received {received} replies, "
              f"{mismatches} mismatches, {len(words) - received} timeouts.")


if __name__ == "__main__":
    main()