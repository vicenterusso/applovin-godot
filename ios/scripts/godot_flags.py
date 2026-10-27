#!/usr/bin/env python3
"""Reads a Godot compile_commands.json and prints what the plugin build needs.

The iOS plugin is a static library linked into the Godot export template, so it must
be compiled with exactly the same defines and include paths as the engine (otherwise
class layouts such as Object's may differ). Instead of hard-coding them per Godot
version we take them from the engine's own compilation database.

Usage:
    godot_flags.py flags   <compile_commands.json>   -> one compiler flag per line
    godot_flags.py objects <compile_commands.json>   -> engine objects to build (generates headers)
    godot_flags.py directory <compile_commands.json> -> directory the flags are relative to
"""

import json
import shlex
import sys

REFERENCE_SOURCE = "core/object/object.cpp"
# Building these objects makes SCons generate every header the plugin includes.
HEADER_SOURCES = ("core/object/object.cpp", "core/object/class_db.cpp", "core/config/engine.cpp")

# Flags that take a separate argument and must be dropped together with it.
DROP_WITH_ARG = {"-o", "-MF", "-MT", "-MQ", "-x"}
DROP = {"-c", "-MMD", "-MD", "-MP"}


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def normalized(path):
    return path.replace("\\", "/")


def find(entries, source):
    for entry in entries:
        if normalized(entry["file"]).endswith(source):
            return entry
    sys.exit(f"error: {source} not found in compilation database")


def arguments(entry):
    if "arguments" in entry:
        return list(entry["arguments"])
    return shlex.split(entry["command"])


def output_of(entry):
    if "output" in entry:
        return entry["output"]
    args = arguments(entry)
    return args[args.index("-o") + 1]


def flags(entry):
    args = arguments(entry)
    # Skip the compiler itself (and an optional launcher such as ccache).
    while args and not args[0].startswith("-"):
        args.pop(0)
    source = normalized(entry["file"])
    result = []
    skip = False
    for arg in args:
        if skip:
            skip = False
            continue
        if arg in DROP_WITH_ARG:
            skip = True
            continue
        if arg in DROP or arg.startswith("-Werror"):
            continue
        if normalized(arg) == source or normalized(arg).endswith("/" + REFERENCE_SOURCE) or arg == REFERENCE_SOURCE:
            continue
        result.append(arg)
    return result


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    mode, path = sys.argv[1], sys.argv[2]
    entries = load(path)
    if mode == "flags":
        print("\n".join(flags(find(entries, REFERENCE_SOURCE))))
    elif mode == "objects":
        print("\n".join(output_of(find(entries, source)) for source in HEADER_SOURCES))
    elif mode == "directory":
        print(find(entries, REFERENCE_SOURCE)["directory"])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
