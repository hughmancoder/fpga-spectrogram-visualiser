#!/usr/bin/env python3
"""Draw a square-wired block diagram of a module from a Yosys JSON netlist using netlistsvg.

Usage: draw_diagram.py <module> <source.sv> <netlist.json> <output.svg>

fft and bar_renderer have no sub-modules, so their logic is grouped into blocks by the section
of source each cell came from. A cell belongs to the most recent marker above its source line.
"""
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

# module: (block for logic before the first marker, [(source text marking a section, block)])
SECTIONS = {
    "fft": (
        "state_machine",
        [
            ("S_COLLECT: begin", "sample_input"),
            ("// compute iterative", "state_machine"),
            ("// Sub dft size", "butterfly_address"),
            ("// Twiddle factor w", "twiddle_rom"),
            ("// Array indices for u", "butterfly_address"),
            ("// Complex multiplication", "complex_multiply"),
            ("// arithmetic shift", "butterfly_add_sub"),
            ("// loops are written", "loop_counters"),
            ("S_MAGNITUDE: begin", "magnitude"),
            ("default: state", "state_machine"),
        ],
    ),
    "bar_renderer": (
        "bar_tracking",
        [
            ("// Horizontal Tracking", "bar_tracking"),
            ("// Introduce 1 cycle delay", "pipeline_delay"),
            ("// Vertical calculation", "colour_picker"),
        ],
    ),
}

HIDDEN_NETS = ("clk", "rst_n")

# Registers and memories are declared away from their logic, so place them by name
NAMED = {
    "fft": {
        "X_re": "fft_ram",
        "X_im": "fft_ram",
        "twiddle_cos_rom": "twiddle_rom",
        "twiddle_sin_rom": "twiddle_rom",
        "sample_index": "sample_input",
        "s": "loop_counters",
        "k": "loop_counters",
        "j": "loop_counters",
        "bin_cnt": "magnitude",
        "bin_idx": "magnitude",
        "mag_out": "magnitude",
        "mag_valid": "magnitude",
    },
}


def block_for_line(line, source_lines, default, sections):
    # The end of a case item is where Yosys puts the state machine's own muxes
    if source_lines[line - 1].strip() == "end":
        return default

    block = default
    for text in source_lines[:line]:
        for marker, section_block in sections:
            if marker in text:
                block = section_block
    return block


def block_for_cell(cell, module, source_lines, net_of_bit):
    default, sections = SECTIONS[module]
    named = NAMED.get(module, {})

    if cell["type"].startswith("$mem"):
        memid = str(cell["parameters"].get("MEMID", "")).lstrip("\\")
        return named.get(memid, default)

    if "Q" in cell["connections"]:
        register = net_of_bit.get(cell["connections"]["Q"][0], ("", 0))[0]
        if register in named:
            return named[register]

    match = re.search(r":(\d+)", cell["attributes"].get("src", ""))
    if match is None:
        return default
    return block_for_line(int(match.group(1)), source_lines, default, sections)


def group_cells(top, module, source_lines):
    """Replace the cells of top with one cell per block, keeping only nets between blocks."""
    # Later names win, so a visible net name replaces a generated one
    net_of_bit = {}
    for name, net in sorted(top["netnames"].items(), key=lambda item: not item[1]["hide_name"]):
        for index, bit in enumerate(net["bits"]):
            net_of_bit[bit] = (name, index)

    blocks = {}
    for cell in top["cells"].values():
        block = block_for_cell(cell, module, source_lines, net_of_bit)
        ins, outs = blocks.setdefault(block, (set(), set()))
        for port, bits in cell["connections"].items():
            direction = cell["port_directions"][port]
            for bit in bits:
                if isinstance(bit, int):
                    (outs if direction == "output" else ins).add(bit)

    driver_of = {}
    for block, (_, outs) in blocks.items():
        for bit in outs:
            driver_of[bit] = block

    used_outside = set()
    for port in top["ports"].values():
        if port["direction"] == "output":
            used_outside.update(port["bits"])
    for block, (ins, _) in blocks.items():
        used_outside.update(bit for bit in ins if driver_of.get(bit) != block)

    readers_of = {}
    for block, (ins, _) in blocks.items():
        for bit in ins:
            if driver_of.get(bit) != block:
                readers_of.setdefault(bit, []).append(block)

    def is_generated(bit):
        return top["netnames"][net_of_bit[bit][0]]["hide_name"] != 0

    # Clock and reset reach every block, so drawing them only adds wires
    hidden_bits = {bit for name in HIDDEN_NETS for bit in top["ports"][name]["bits"]}

    cells = {}
    for block, (ins, outs) in blocks.items():
        connections, directions = {}, {}

        # Generated nets have meaningless names, so bundle them into one bus per connection
        for bit in sorted(ins - hidden_bits):
            if driver_of.get(bit) == block:
                continue
            port = f"from_{driver_of[bit]}" if is_generated(bit) else net_of_bit[bit][0]
            connections.setdefault(port, []).append(bit)
            directions[port] = "input"
        for bit in sorted(outs & used_outside):
            port = f"to_{readers_of[bit][0]}" if is_generated(bit) else net_of_bit[bit][0]
            connections.setdefault(port, []).append(bit)
            directions[port] = "output"

        cells[block] = {"type": block, "port_directions": directions, "connections": connections}

    top["cells"] = cells
    for name in HIDDEN_NETS:
        del top["ports"][name]


def main():
    module, source_path = sys.argv[1], Path(sys.argv[2])
    netlist_path, svg_path = Path(sys.argv[3]), Path(sys.argv[4])

    netlist = json.loads(netlist_path.read_text())
    top = netlist["modules"][module]

    if module in SECTIONS:
        group_cells(top, module, source_path.read_text().splitlines())
    else:
        # Name each block after its instance so reset_sync_audio and reset_sync_pixel can be
        # told apart and no parameter hashes appear
        for name, cell in top["cells"].items():
            if name.startswith("u_"):
                cell["type"] = name.removeprefix("u_")

    clean_path = netlist_path.with_suffix(".clean.json")
    clean_path.write_text(json.dumps({"modules": {module: top}}))

    if shutil.which("netlistsvg") is None:
        sys.exit("netlistsvg not found. Install it with: npm install -g netlistsvg@1.0.2")

    subprocess.run(["netlistsvg", str(clean_path), "-o", str(svg_path)], check=True)

    # netlistsvg leaves the background transparent, which is unreadable in dark themes
    svg = svg_path.read_text()
    svg_path.write_text(svg.replace("<svg ", '<svg style="background:#fff" ', 1))


if __name__ == "__main__":
    main()
