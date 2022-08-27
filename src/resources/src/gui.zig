const main = @import("resources.zig");
const GPUStats = main.GPUStats;
const DemoState = main.DemoState;
const std = @import("std");
const zgpu = @import("zgpu");
const zgui = zgpu.zgui;
const wgpu = zgpu.wgpu;
const Shapes = @import("shapes.zig");
const StagingBuffer = main.StagingBuffer;
const Statistics = @import("simulation.zig").Statistics;

pub fn update(demo: *DemoState) void {
    updateStats(demo);
    zgpu.gui.newFrame(demo.gctx.swapchain_descriptor.width, demo.gctx.swapchain_descriptor.height);
    if (zgui.begin("Settings", .{})) {
        if (zgui.beginTabBar("My Tab Bar")) {
            if (zgui.beginTabItem("Parameters")) {
                parameters(demo);
                zgui.endTabItem();
            }

            if (zgui.beginTabItem("Statistics")) {
                plots(demo);
                zgui.endTabItem();
            }
            zgui.endTabBar();
        }
        zgui.end();
    }
}

fn getGPUStatistics(demo: *DemoState) [3]i32 {
    var buf: StagingBuffer = .{
        .slice = null,
        .buffer = demo.gctx.lookupResource(demo.stats_mapped_buffer).?,
    };
    buf.buffer.mapAsync(.{ .read = true },
                        0,
                        @sizeOf(i32) * 3,
                        main.buffersMappedCallback,
                        @ptrCast(*anyopaque, &buf));
    wait_loop: while (true) {
        demo.gctx.device.tick();
        if (buf.slice == null) {
            continue :wait_loop;
        }
        break;
    }

    const stats_data = [_][3]i32{ [3]i32{ 0, 0, 0 }, };
    demo.gctx.queue.writeBuffer(demo.gctx.lookupResource(demo.stats_buffer).?, 0, [3]i32, stats_data[0..]);
    demo.stats.buffer.unmap();
    return buf.slice.?[0];
}

fn updateStats(demo: *DemoState) void {
    const current_time = @floatCast(f32, demo.gctx.stats.time);
    const current_second = @floor(current_time);
    const stats = demo.sim.stats;
    const previous_second = stats.second;
    if (previous_second < current_second) {
        const gpu_stats = getGPUStatistics(demo);
        const vec_stats: @Vector(4, i32) = [_]i32{ gpu_stats[0], gpu_stats[1], gpu_stats[2], stats.max_stat_recorded};
        const max_stat = @reduce(.Max, vec_stats);
        demo.sim.stats.num_transactions.append(gpu_stats[0]) catch unreachable;
        demo.sim.stats.second = current_second;
        demo.sim.stats.max_stat_recorded = max_stat;
        demo.sim.stats.num_empty_consumers.append(gpu_stats[1]) catch unreachable;
        demo.sim.stats.num_total_producer_inventory.append(gpu_stats[2]) catch unreachable;
    }
}

fn plots(demo: *DemoState) void {
    const stats = demo.sim.stats;
    const num_transactions = stats.num_transactions.items;
    const num_empty_consumers = stats.num_empty_consumers.items;
    const tpi = stats.num_total_producer_inventory.items;
    const window_size = zgui.getWindowSize();
    const tab_bar_height = 100;
    const margin = 50;
    const plot_width = window_size[0] - margin;
    const plot_height = window_size[1] - tab_bar_height - margin;

    if (zgui.beginPlot("Statistics", plot_width, plot_height)) {
        zgui.setupXAxisLimits(0, @floatCast(f64, stats.second - 1));
        zgui.setupYAxisLimits(0, @intToFloat(f64, stats.max_stat_recorded + @divFloor(stats.max_stat_recorded, 2) + 1));
        zgui.plotLineValues("Transactions", num_transactions[0..]);
        zgui.plotLineValues("Empty Consumers", num_empty_consumers[0..]);
        zgui.plotLineValues("Total Producer Inventory", tpi[0..]);
        zgui.endPlot();
    }
}

fn parameters(demo: *DemoState) void {
    zgui.pushItemWidth(zgui.getContentRegionAvailWidth() * 0.4);
    zgui.bulletText(
        "Average :  {d:.3} ms/frame ({d:.1} fps)",
        .{ demo.gctx.stats.average_cpu_time, demo.gctx.stats.fps },
    );
    zgui.spacing();
    _ = zgui.sliderInt("Number of Producers", .{ .v = &demo.sim.params.num_producers, .min = 1, .max = 100 });
    _ = zgui.sliderInt("Production Rate", .{ .v = &demo.sim.params.production_rate, .min = 1, .max = 100 });
    _ = zgui.sliderInt("Giving Rate", .{ .v = &demo.sim.params.giving_rate, .min = 1, .max = 1000 });
    _ = zgui.sliderInt("Number of Consumers", .{ .v = &demo.sim.params.num_consumers, .min = 1, .max = 10000 });
    _ = zgui.sliderInt("Consumption Rate", .{ .v = &demo.sim.params.consumption_rate, .min = 1, .max = 100 });
    _ = zgui.sliderFloat("Moving Rate", .{ .v = &demo.sim.params.moving_rate, .min = 1.0, .max = 20 });
    if (zgui.button("Start", .{})) {
        const compute_bgl = demo.gctx.createBindGroupLayout(&.{
            zgpu.bglBuffer(0, .{ .compute = true }, .storage, true, 0),
            zgpu.bglBuffer(1, .{ .compute = true }, .storage, true, 0),
            zgpu.bglBuffer(2, .{ .compute = true }, .storage, true, 0),
        });
        defer demo.gctx.releaseResource(compute_bgl);
        demo.sim.createAgents();
        demo.producer_buffer = Shapes.createProducerBuffer(demo.gctx, demo.sim.producers);
        demo.consumer_buffer = Shapes.createConsumerBuffer(demo.gctx, demo.sim.consumers);
        demo.consumer_bind_group = Shapes.createBindGroup(demo.gctx, demo.sim, compute_bgl, demo.consumer_buffer, demo.producer_buffer, demo.stats_buffer);
    }
}
