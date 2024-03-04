# DMIDecode

My first project while learning Zig. This is a Zig implementation for parsing the output of the `dmidecode` command. This is a port of [dmidecode-nim](https://github.com/xmonader/nim-dmidecode).

## Quick Start

```zig
const std = @import("std");
const DMIDecode = @import("dmidecode.zig").DMIDecode;

pub fn main() !void {
    var parser = DMIDecode.init(std.heap.page_allocator);
    defer parser.deinit();

    const sections = try parser.parse(
        \\Handle 0x0036, DMI type 43, 31 bytes
        \\TPM Device
        \\	Vendor ID: INTC
        \\	Specification Version: 2.0
        \\	Firmware Revision: 500.5
        \\	Strings:
        \\          Insyde_ASF_001
        \\          Insyde_ASF_002
        \\
    );

    const section: DMIDecode.Section = sections.get("TPM Device").?;
    std.debug.print("Handle: {s}, Title: {s}\n", .{ section.handleLine, section.title });

    const vendorID = section.props.get("Vendor ID").?.val;
    std.debug.print("Vendor ID: {s}\n", .{vendorID});

    const strings = section.props.get("Strings").?.items;
    std.debug.print("Strings: {s}, {s}\n", .{ strings.items[0], strings.items[0] });
}
```

## Installation

1. Declare dmidecode as a project dependency with `zig fetch`:

```bash
zig fetch --save git+https://github.com/soheil-01/dmidecode.git#main
```

2. Expose dmidecode as a module in your project's `build.zig`:

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const opts = .{ .target = target, .optimize = optimize };      // 👈
    const dmidecode_mod = b.dependency("dmidecode", opts).module("dmidecode"); // 👈

    const exe = b.addExecutable(.{
        .name = "my-project",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("dmidecode", dmidecode_mod); // 👈

    // ...
}
```

3. Import dmidecode into your code:

```zig
const dmidecode = @import("dmidecode");
```
