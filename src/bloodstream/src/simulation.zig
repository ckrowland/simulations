const std = @import("std");
const array = std.ArrayList;
const random = std.crypto.random;

const Self = @This();

params: struct {
    num_producers: i32,
    production_rate: i32,
    giving_rate: i32,
    max_inventory: i32,
    num_consumers: i32,
    consumption_rate: i32,
    velocity: f32,
    acceleration: f32,
    jerk: f32,
    producer_width: f32,
    consumer_radius: f32,
    num_consumer_sides: u32,
},
coordinate_size: struct {
    min_x: i32,
    min_y: i32,
    max_x: i32,
    max_y: i32,
},
consumers: array(Consumer),
stats: Statistics,

pub const Consumer = struct {
    position: @Vector(4, f32),
    color: @Vector(4, f32),
    velocity: @Vector(4, f32),
    acceleration: @Vector(4, f32),
    consumption_rate: i32,
    jerk: f32,
    inventory: i32,
    radius: f32,
    producer_id: i32,
};

pub const Statistics = struct {
    num_transactions: array(i32),
    second: i32,
    max_stat_recorded: i32,
    num_empty_consumers: array(i32),
    num_total_producer_inventory: array(i32),
};

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .params = .{
            .num_producers = 10,
            .production_rate = 100,
            .giving_rate = 10,
            .max_inventory = 10000,
            .num_consumers = 1000,
            .consumption_rate = 10,
            .velocity = 50.0,
            .acceleration = 3.0,
            .jerk = 0.1,
            .producer_width = 40.0,
            .consumer_radius = 10.0,
            .num_consumer_sides = 20,
        },
        .coordinate_size = .{
            .min_x = -1000,
            .min_y = 0,
            .max_x = 1800,
            .max_y = 700,
        },
        .consumers = array(Consumer).init(allocator),
        .stats = .{
            .num_transactions = array(i32).init(allocator),
            .second = 0,
            .max_stat_recorded = 0,
            .num_empty_consumers = array(i32).init(allocator),
            .num_total_producer_inventory = array(i32).init(allocator), 
        },
    };
}

pub fn deinit(self: *Self) void {
    self.consumers.deinit();
    self.stats.num_transactions.deinit();
    self.stats.num_empty_consumers.deinit();
    self.stats.num_total_producer_inventory.deinit();
}

pub fn createAgents(self: *Self) void {
    self.consumers.clearAndFree();
    self.stats.num_transactions.clearAndFree();
    self.stats.num_empty_consumers.clearAndFree();
    self.stats.num_total_producer_inventory.clearAndFree();
    self.stats.num_transactions.append(0) catch unreachable;
    self.stats.num_empty_consumers.append(0) catch unreachable;
    self.stats.num_total_producer_inventory.append(0) catch unreachable;
    self.stats.second = 0;
    self.stats.max_stat_recorded = 0;
    createConsumers(self);
}

pub fn supplyShock(self: *Self) void {
    for (self.consumers.items) |_, i| {
        self.consumers.items[i].inventory = 0;
    }
}

pub fn createConsumers(self: *Self) void {
    var i: usize = 0;

    while (i < self.params.num_consumers) {
        const x = @intToFloat(f32, random.intRangeAtMost(i32, self.coordinate_size.min_x, self.coordinate_size.max_x));
        const y = @intToFloat(f32, random.intRangeAtMost(i32, self.coordinate_size.min_y, self.coordinate_size.max_y));
        const pos = @Vector(4, f32){ x, y, 0.0, 0.0 };
        const red = @Vector(4, f32){ 1.0, 0.0, 0.0, 0.0 };
        const vel = @Vector(4, f32){ 0.0, -2.0, 0.0, 0.0 };
        const acc = @Vector(4, f32){ 0.0, -0.1, 0.0, 0.0 };
        const c = Consumer{
            .position = pos,
            .color = red,
            .velocity = vel,
            .acceleration = acc,
            .consumption_rate = self.params.consumption_rate,
            .jerk = self.params.jerk,
            .inventory = 0,
            .radius = self.params.consumer_radius,
            .producer_id = 1000,
        };
        self.consumers.append(c) catch unreachable;
        i += 1;
    }
}