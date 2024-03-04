const std = @import("std");

pub const DMIDecode = struct {
    allocator: std.mem.Allocator,
    sections: std.StringHashMap(Section),

    pub fn init(allocator: std.mem.Allocator) DMIDecode {
        return DMIDecode{ .allocator = allocator, .sections = std.StringHashMap(Section).init(allocator) };
    }

    pub fn deinit(self: *DMIDecode) void {
        var sectionsIter = self.sections.valueIterator();
        while (sectionsIter.next()) |section| {
            var propsIter = section.*.props.valueIterator();
            while (propsIter.next()) |prop| {
                if (prop.* == .items) {
                    prop.items.deinit();
                }
            }
            section.*.props.deinit();
        }
        self.sections.deinit();
    }

    pub const Property = union(enum) { val: []const u8, items: std.ArrayList([]const u8) };

    pub const Section = struct {
        handleLine: []const u8,
        title: []const u8,
        props: std.StringHashMap(Property),
    };

    const ParserState = enum { no_op, section_name, read_key_value, read_list };

    fn getIndentLevel(line: []const u8) usize {
        for (line, 0..) |c, i| {
            if (!std.ascii.isWhitespace(c)) return i;
        }
        return 0;
    }

    pub fn parse(self: *DMIDecode, source: []const u8) std.mem.Allocator.Error!std.StringHashMap(Section) {
        var state: ParserState = .no_op;

        var linesIter = std.mem.splitAny(u8, source, "\n");
        var lines = std.ArrayList([]const u8).init(self.allocator);
        while (linesIter.next()) |line| {
            try lines.append(line);
        }
        defer lines.deinit();

        var s: ?Section = null;
        var p: ?Property = null;

        var k: []const u8 = "";
        var v: []const u8 = "";

        for (lines.items, 0..) |line, i| {
            if (std.mem.startsWith(u8, line, "Handle")) {
                s = Section{ .handleLine = line, .title = undefined, .props = std.StringHashMap(Property).init(self.allocator) };
                state = .section_name;
                continue;
            }
            if (line.len == 0) {
                if (s) |section| {
                    try self.sections.put(section.title, section);
                    s = null;
                }
                continue;
            }

            if (s == null) continue;

            if (state == .section_name) {
                s.?.title = line;
                state = .read_key_value;
            } else if (state == .read_key_value) {
                var lineIter = std.mem.splitAny(u8, line, ":");
                k = std.mem.trim(u8, lineIter.next().?, &std.ascii.whitespace);

                const value = lineIter.next().?;

                if (value.len > 0) {
                    v = std.mem.trim(u8, value, &std.ascii.whitespace);
                    p = .{ .val = v };
                    try s.?.props.put(k, p.?);
                } else {
                    p = .{ .items = std.ArrayList([]const u8).init(self.allocator) };

                    if (i < lines.items.len - 1 and getIndentLevel(line) < getIndentLevel(lines.items[i + 1])) {
                        state = .read_list;
                    } else {
                        try s.?.props.put(k, p.?);
                    }
                }
            } else if (state == .read_list) {
                try p.?.items.append(std.mem.trim(u8, line, &std.ascii.whitespace));
                if (i < lines.items.len - 1 and getIndentLevel(line) > getIndentLevel(lines.items[i + 1])) {
                    state = .read_key_value;
                    try s.?.props.put(k, p.?);
                }
            }
        }

        return self.sections;
    }
};

test "dmidecode: test DMIDecode" {
    var parser = DMIDecode.init(std.testing.allocator);
    defer parser.deinit();

    const sections = try parser.parse(
        \\
        \\Handle 0x0004, DMI type 4, 48 bytes
        \\Processor Information
        \\	Socket Designation: U3E1
        \\	Type: Central Processor
        \\	Flags:
        \\		FPU
        \\		VME
        \\	Version: Intel(R)
        \\	Voltage: 0.7 V
        \\
        \\Handle 0x0005, DMI type 7, 27 bytes
        \\Cache Information
        \\	Socket Designation: L1 Cache
        \\	Configuration: Enabled
        \\	Operational Mode: Write Back
        \\
        \\End Of Table
    );

    try std.testing.expect(sections.count() == 2);

    const section1 = sections.get("Processor Information").?;
    try std.testing.expectEqualStrings("Handle 0x0004, DMI type 4, 48 bytes", section1.handleLine);
    try std.testing.expectEqualStrings("Processor Information", section1.title);

    const socketDesignation = section1.props.get("Socket Designation").?.val;
    try std.testing.expectEqualStrings("U3E1", socketDesignation);

    const flags = section1.props.get("Flags").?.items;
    try std.testing.expectEqualStrings(flags.items[0], "FPU");
    try std.testing.expectEqualStrings(flags.items[1], "VME");

    const section2 = sections.get("Cache Information").?;
    try std.testing.expectEqualStrings("Handle 0x0005, DMI type 7, 27 bytes", section2.handleLine);
    try std.testing.expectEqualStrings("Cache Information", section2.title);

    const configuration = section2.props.get("Configuration").?.val;
    try std.testing.expectEqualStrings("Enabled", configuration);

    const operationalMode = section2.props.get("Operational Mode").?.val;
    try std.testing.expectEqualStrings("Write Back", operationalMode);
}
