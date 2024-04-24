const std = @import("std");
const array = std.ArrayList;
const random = std.crypto.random;
const Allocator = std.mem.Allocator;
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const Wgpu = @import("wgpu.zig");
const Main = @import("main.zig");
const DemoState = Main.DemoState;
const Parameters = Main.Parameters;
const Camera = @import("camera.zig");

const Self = @This();

absolute_home: [4]i32 = .{ 0, 0, 0, 0 },
home: [4]f32 = .{ 0, 0, 0, 0 },
color: [4]f32 = .{ 0, 0, 0, 0 },
production_rate: u32 = 0,
inventory: i32 = 0,
max_inventory: u32 = 0,
price: u32 = 1,

pub const z_pos = 0;
pub const Parameter = enum {
    production_rate,
    supply_shock,
    max_inventory,
};

pub const DEFAULT_PRODUCTION_RATE: u32 = 300;
pub const DEFAULT_MAX_INVENTORY: u32 = 10000;
pub const Args = struct {
    absolute_home: [2]i32,
    home: [2]f32,
    color: [4]f32 = .{ 1, 1, 1, 0 },
    production_rate: u32 = DEFAULT_PRODUCTION_RATE,
    inventory: i32 = 0,
    max_inventory: u32 = DEFAULT_MAX_INVENTORY,
    price: u32 = 1,
};

pub fn generateBulk(demo: *DemoState, num: u32) void {
    var i: usize = 0;
    while (i < num) {
        const x = random.intRangeAtMost(i32, Camera.MIN_X, Camera.MAX_X);
        const y = random.intRangeAtMost(i32, Camera.MIN_Y, Camera.MAX_Y);
        createAndAppend(demo.gctx, .{
            .obj_buf = &demo.buffers.data.producers,
            .producer = .{
                .absolute_home = .{ x, y },
                .home = [2]f32{
                    @as(f32, @floatFromInt(x)) * demo.params.aspect,
                    @as(f32, @floatFromInt(y)),
                },
                .production_rate = demo.params.production_rate,
                .inventory = @as(i32, @intCast(demo.params.max_inventory)),
                .max_inventory = demo.params.max_inventory,
                .price = demo.params.price,
            },
        });
        i += 1;
    }
}

pub const AppendArgs = struct {
    producer: Args,
    obj_buf: *Wgpu.ObjectBuffer(Self),
};
pub fn createAndAppend(gctx: *zgpu.GraphicsContext, args: AppendArgs) void {
    const abs_home = args.producer.absolute_home;
    const home = args.producer.home;
    var producers: [1]Self = .{
        .{
            .absolute_home = .{ abs_home[0], abs_home[1], z_pos, 1 },
            .home = .{ home[0], home[1], z_pos, 1 },
            .color = args.producer.color,
            .production_rate = args.producer.production_rate,
            .inventory = args.producer.inventory,
            .max_inventory = args.producer.max_inventory,
            .price = args.producer.price,
        },
    };
    Wgpu.appendBuffer(gctx, Self, .{
        .num_old_structs = @as(u32, @intCast(args.obj_buf.list.items.len)),
        .buf = args.obj_buf.buf,
        .structs = producers[0..],
    });
    args.obj_buf.list.append(producers[0]) catch unreachable;
    args.obj_buf.mapping.num_structs += 1;
}

pub fn setParamAll(
    demo: *DemoState,
    comptime tag: []const u8,
    comptime T: type,
    num: T,
) void {
    const buf = demo.buffers.data.producers.buf;
    const resource = demo.gctx.lookupResource(buf).?;
    const field_enum = @field(std.meta.FieldEnum(Self), tag);
    const field_type = std.meta.FieldType(Self, field_enum);
    std.debug.assert(field_type == T);

    const struct_offset = @offsetOf(Self, tag);
    for (demo.buffers.data.producers.list.items, 0..) |_, i| {
        const offset = i * @sizeOf(Self) + struct_offset;
        demo.gctx.queue.writeBuffer(resource, offset, field_type, &.{num});
    }
}
