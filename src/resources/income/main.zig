const std = @import("std");
const math = std.math;
const random = std.crypto.random;
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zgui = @import("zgui");
const zm = @import("zmath");
const zstbi = @import("zstbi");
const Statistics = @import("statistics.zig");
const gui = @import("gui.zig");
const Wgpu = @import("wgpu.zig");
const config = @import("config.zig");
const Consumer = @import("consumer.zig");
const Producer = @import("producer.zig");
const Camera = @import("camera.zig");
const Square = @import("square.zig");
const Circle = @import("circle.zig");
const Callbacks = @import("callbacks.zig");

pub const MAX_NUM_PRODUCERS = 100;
pub const MAX_NUM_CONSUMERS = 40000;
pub const NUM_CONSUMER_SIDES = 40;
pub const PRODUCER_WIDTH = 40;

pub const DemoState = struct {
    gctx: *zgpu.GraphicsContext,
    window: *zglfw.Window,
    allocator: std.mem.Allocator,
    running: bool = false,
    push_coord_update: bool = false,
    push_restart: bool = false,
    content_scale: f32,
    params: Parameters,
    stats: Statistics,
    imgui_windows: [2]gui.FullPos,
    render_pipelines: struct {
        circle: zgpu.RenderPipelineHandle,
        square: zgpu.RenderPipelineHandle,
    },
    compute_pipelines: struct {
        consumer: zgpu.ComputePipelineHandle,
        producer: zgpu.ComputePipelineHandle,
    },
    bind_groups: struct {
        render: zgpu.BindGroupHandle,
        compute: zgpu.BindGroupHandle,
    },
    buffers: struct {
        data: struct {
            consumers: Wgpu.ObjectBuffer(Consumer),
            producers: Wgpu.ObjectBuffer(Producer),
            stats: Wgpu.ObjectBuffer(u32),
        },
        index: struct {
            circle: zgpu.BufferHandle,
        },
        vertex: struct {
            circle: zgpu.BufferHandle,
            square: zgpu.BufferHandle,
        },
    },
    depth_texture: zgpu.TextureHandle,
    depth_texture_view: zgpu.TextureViewHandle,
};

pub const Parameters = struct {
    aspect: f32,
    max_num_stats: u32 = 3,
    num_producers: u32 = 6,
    num_consumers: u32 = 5000,
    production_rate: u32 = 300,
    max_demand_rate: u32 = 100,
    max_inventory: u32 = 10000,
    moving_rate: f32 = 5.0,
    consumer_radius: f32 = 1.0,
    num_consumer_sides: u32 = 20,
    median_income: f32 = 0.01,
    plot_hovered: bool = false,
    price: u32 = 1,
    consumer_incomes: [4]doubleXY(f64) = [_]doubleXY(f64){
        doubleXY(f64).init(f64, 100, 0),
        doubleXY(f64).init(f64, 200, 0),
        doubleXY(f64).init(f64, 300, 0),
        doubleXY(f64).init(f64, 400, 4000),
    },

    pub fn doubleXY(comptime T: type) type {
        return struct {
            old: struct { income: T, num: T },
            new: struct { income: T, num: T },
            num: u32 = 0,

            pub fn init(comptime Ti: type, income: Ti, num: Ti) doubleXY(Ti) {
                return doubleXY(Ti){
                    .old = .{ .income = income, .num = num },
                    .new = .{ .income = income, .num = num },
                };
            }
        };
    }

    pub fn clearConsumerIncomesNum(self: *Parameters) void {
        for (&self.consumer_incomes) |*ci| {
            ci.num = 0;
        }
    }
};

pub fn init(allocator: std.mem.Allocator, window: *zglfw.Window) !DemoState {
    const gctx = try zgpu.GraphicsContext.create(
        allocator,
        .{
            .window = window,
            .fn_getTime = @ptrCast(&zglfw.getTime),
            .fn_getFramebufferSize = @ptrCast(&zglfw.Window.getFramebufferSize),
            .fn_getWin32Window = @ptrCast(&zglfw.getWin32Window),
            .fn_getX11Display = @ptrCast(&zglfw.getX11Display),
            .fn_getX11Window = @ptrCast(&zglfw.getX11Window),
            .fn_getWaylandDisplay = @ptrCast(&zglfw.getWaylandDisplay),
            .fn_getWaylandSurface = @ptrCast(&zglfw.getWaylandWindow),
            .fn_getCocoaWindow = @ptrCast(&zglfw.getCocoaWindow),
        },
        .{},
    );
    const params = Parameters{
        .aspect = Camera.getAspectRatio(gctx),
    };

    const consumer_object = Wgpu.createObjectBuffer(
        allocator,
        gctx,
        Consumer,
        MAX_NUM_CONSUMERS,
        0,
    );

    const producer_object = Wgpu.createObjectBuffer(
        allocator,
        gctx,
        Producer,
        MAX_NUM_PRODUCERS,
        0,
    );

    const stats_object = Wgpu.createObjectBuffer(
        allocator,
        gctx,
        u32,
        Statistics.NUM_STATS,
        Statistics.NUM_STATS,
    );
    const compute_bind_group = Wgpu.createComputeBindGroup(gctx, .{
        .consumer = consumer_object.buf,
        .producer = producer_object.buf,
        .stats = stats_object.buf,
    });
    const depth = Wgpu.createDepthTexture(gctx);

    return DemoState{
        .gctx = gctx,
        .window = window,
        .content_scale = getContentScale(window),
        .imgui_windows = .{
            .{
                .pos = .{ .x = 0, .y = 0 },
                .size = .{ .x = 0.25, .y = 0.75 },
                .id = .{
                    .num = 0,
                    .str = "0",
                },
            },
            .{
                .pos = .{ .x = 0, .y = 0.75, .margin = .{ .top = false } },
                .size = .{ .x = 1, .y = 0.25, .margin = .{ .top = false } },
                .id = .{
                    .num = 1,
                    .str = "1",
                },
            },
        },
        .render_pipelines = .{
            .circle = Wgpu.createRenderPipeline(gctx, config.cpi),
            .square = Wgpu.createRenderPipeline(gctx, config.ppi),
        },
        .compute_pipelines = .{
            .producer = Wgpu.createComputePipeline(gctx, config.pcpi),
            .consumer = Wgpu.createComputePipeline(gctx, config.ccpi),
        },
        .bind_groups = .{
            .render = Wgpu.createUniformBindGroup(gctx),
            .compute = compute_bind_group,
        },
        .buffers = .{
            .data = .{
                .consumers = consumer_object,
                .producers = producer_object,
                .stats = stats_object,
            },
            .index = .{
                .circle = Circle.createIndexBuffer(gctx, NUM_CONSUMER_SIDES),
            },
            .vertex = .{
                .circle = Circle.createVertexBuffer(
                    gctx,
                    NUM_CONSUMER_SIDES,
                    params.consumer_radius,
                ),
                .square = Square.createVertexBuffer(gctx, PRODUCER_WIDTH),
            },
        },
        .depth_texture = depth.texture,
        .depth_texture_view = depth.view,
        .allocator = allocator,
        .params = params,
        .stats = Statistics.init(allocator),
    };
}

pub fn update(demo: *DemoState) void {
    const sd = demo.gctx.swapchain_descriptor;
    zgui.backend.newFrame(sd.width, sd.height);
    if (demo.push_restart) restartSimulation(demo);
    if (demo.push_coord_update) updateAspectRatio(demo);

    Wgpu.runCallbackIfReady(u32, &demo.buffers.data.stats.mapping);
    Wgpu.runCallbackIfReady(Producer, &demo.buffers.data.producers.mapping);
    Wgpu.runCallbackIfReady(Consumer, &demo.buffers.data.consumers.mapping);

    // zgui.plot.showDemoWindow(null);
    gui.update(demo);

    if (demo.running) {
        Statistics.generateAndFillRandomColor(demo);
        const current_time = @as(f32, @floatCast(demo.gctx.stats.time));
        const seconds_passed = current_time - demo.stats.second;
        if (seconds_passed >= 1) {
            demo.stats.second = current_time;
            Wgpu.getAllAsync(demo, u32, Callbacks.numTransactions);
            Wgpu.getAllAsync(demo, Consumer, Callbacks.consumerStats);
            Wgpu.getAllAsync(demo, Producer, Callbacks.totalInventory);
        }
    }
}

pub fn draw(demo: *DemoState) void {
    const gctx = demo.gctx;
    const cam_world_to_clip = Camera.getObjectToClipMat(gctx);

    const back_buffer_view = gctx.swapchain.getCurrentTextureView();
    defer back_buffer_view.release();

    const commands = commands: {
        const encoder = gctx.device.createCommandEncoder(null);
        defer encoder.release();

        const data = demo.buffers.data;
        const num_consumers = @as(u32, @intCast(data.consumers.list.items.len));
        const num_producers = @as(u32, @intCast(data.producers.list.items.len));

        // Compute shaders
        if (demo.running) {
            pass: {
                const pcp = gctx.lookupResource(demo.compute_pipelines.producer) orelse break :pass;
                const ccp = gctx.lookupResource(demo.compute_pipelines.consumer) orelse break :pass;
                const bg = gctx.lookupResource(demo.bind_groups.compute) orelse break :pass;

                const pass = encoder.beginComputePass(null);
                defer {
                    pass.end();
                    pass.release();
                }
                pass.setBindGroup(0, bg, &.{});

                pass.setPipeline(pcp);
                pass.dispatchWorkgroups(@divFloor(num_producers, 64) + 1, 1, 1);

                pass.setPipeline(ccp);
                pass.dispatchWorkgroups(@divFloor(num_consumers, 64) + 1, 1, 1);
            }
        }

        // Copy data to mapped buffers so we can retrieve it on demand
        pass: {
            if (!demo.buffers.data.stats.mapping.waiting) {
                const s = gctx.lookupResource(data.stats.buf) orelse break :pass;
                const s_info = gctx.lookupResourceInfo(data.stats.buf) orelse break :pass;
                const sm = gctx.lookupResource(data.stats.mapping.buf) orelse break :pass;
                const s_size = @as(usize, @intCast(s_info.size));
                encoder.copyBufferToBuffer(s, 0, sm, 0, s_size);
            }

            if (!demo.buffers.data.producers.mapping.waiting) {
                const p = gctx.lookupResource(data.producers.buf) orelse break :pass;
                const p_info = gctx.lookupResourceInfo(data.producers.buf) orelse break :pass;
                const pm = gctx.lookupResource(data.producers.mapping.buf) orelse break :pass;
                const p_size = @as(usize, @intCast(p_info.size));
                encoder.copyBufferToBuffer(p, 0, pm, 0, p_size);
            }

            if (!demo.buffers.data.consumers.mapping.waiting) {
                const c = gctx.lookupResource(data.consumers.buf) orelse break :pass;
                const c_info = gctx.lookupResourceInfo(data.consumers.buf) orelse break :pass;
                const cm = gctx.lookupResource(data.consumers.mapping.buf) orelse break :pass;
                const c_size = @as(usize, @intCast(c_info.size));
                encoder.copyBufferToBuffer(c, 0, cm, 0, c_size);
            }
        }

        // Draw the circles and squares in our defined viewport
        pass: {
            const svb_info = gctx.lookupResourceInfo(demo.buffers.vertex.square) orelse break :pass;
            const pb_info = gctx.lookupResourceInfo(demo.buffers.data.producers.buf) orelse break :pass;
            const cvb_info = gctx.lookupResourceInfo(demo.buffers.vertex.circle) orelse break :pass;
            const cb_info = gctx.lookupResourceInfo(demo.buffers.data.consumers.buf) orelse break :pass;
            const cib_info = gctx.lookupResourceInfo(demo.buffers.index.circle) orelse break :pass;
            const square_rp = gctx.lookupResource(demo.render_pipelines.square) orelse break :pass;
            const circle_rp = gctx.lookupResource(demo.render_pipelines.circle) orelse break :pass;
            const render_bind_group = gctx.lookupResource(demo.bind_groups.render) orelse break :pass;
            const depth_view = gctx.lookupResource(demo.depth_texture_view) orelse break :pass;

            const color_attachments = [_]wgpu.RenderPassColorAttachment{.{
                .view = back_buffer_view,
                .load_op = .clear,
                .store_op = .store,
            }};
            const depth_attachment = wgpu.RenderPassDepthStencilAttachment{
                .view = depth_view,
                .depth_load_op = .clear,
                .depth_store_op = .store,
                .depth_clear_value = 1.0,
            };
            const render_pass_info = wgpu.RenderPassDescriptor{
                .color_attachment_count = color_attachments.len,
                .color_attachments = &color_attachments,
                .depth_stencil_attachment = &depth_attachment,
            };
            const pass = encoder.beginRenderPass(render_pass_info);
            defer {
                pass.end();
                pass.release();
            }

            const sd = gctx.swapchain_descriptor;
            const width = @as(f32, @floatFromInt(sd.width));
            const xOffset = width / 4;
            const height = @as(f32, @floatFromInt(sd.height));
            const yOffset = height / 4;
            pass.setViewport(xOffset, 0, width - xOffset, height - yOffset, 0, 1);

            var mem = gctx.uniformsAllocate(zm.Mat, 1);
            mem.slice[0] = cam_world_to_clip;
            pass.setBindGroup(0, render_bind_group, &.{mem.offset});

            const num_indices_circle = @as(
                u32,
                @intCast(cib_info.size / @sizeOf(f32)),
            );
            pass.setPipeline(circle_rp);
            pass.setVertexBuffer(0, cvb_info.gpuobj.?, 0, cvb_info.size);
            pass.setVertexBuffer(1, cb_info.gpuobj.?, 0, cb_info.size);
            pass.setIndexBuffer(cib_info.gpuobj.?, .uint32, 0, cib_info.size);
            pass.drawIndexed(num_indices_circle, num_consumers, 0, 0, 0);

            pass.setPipeline(square_rp);
            pass.setVertexBuffer(0, svb_info.gpuobj.?, 0, svb_info.size);
            pass.setVertexBuffer(1, pb_info.gpuobj.?, 0, pb_info.size);
            pass.draw(6, num_producers, 0, 0);
        }

        // Draw ImGui
        {
            const pass = zgpu.beginRenderPassSimple(
                encoder,
                .load,
                back_buffer_view,
                null,
                null,
                null,
            );
            defer zgpu.endReleasePass(pass);
            zgui.backend.draw(pass);
        }

        break :commands encoder.finish(null);
    };
    defer commands.release();

    gctx.submit(&.{commands});

    if (demo.gctx.present() == .swap_chain_resized) {
        demo.content_scale = getContentScale(demo.window);
        setImguiContentScale(demo.content_scale);
        updateAspectRatio(demo);
    }
}

pub fn restartSimulation(demo: *DemoState) void {
    const consumer_waiting = demo.buffers.data.consumers.mapping.waiting;
    const producer_waiting = demo.buffers.data.producers.mapping.waiting;
    const stats_waiting = demo.buffers.data.stats.mapping.waiting;
    if (consumer_waiting or producer_waiting or stats_waiting) {
        demo.push_restart = true;
        return;
    }

    Wgpu.clearObjBuffer(demo.gctx, Consumer, &demo.buffers.data.consumers);
    Wgpu.clearObjBuffer(demo.gctx, Producer, &demo.buffers.data.producers);
    Wgpu.clearObjBuffer(demo.gctx, u32, &demo.buffers.data.stats);
    demo.buffers.data.stats.mapping.num_structs = Statistics.NUM_STATS;
    demo.params.clearConsumerIncomesNum();

    Statistics.setNum(demo, demo.params.num_consumers, .consumers);
    Statistics.setNum(demo, demo.params.num_producers, .producers);
    Consumer.generateFromParams(demo);
    Producer.generateBulk(demo, demo.params.num_producers);
    demo.stats.clear();
    demo.push_restart = false;
}

pub fn updateDepthTexture(demo: *DemoState) void {
    // Release old depth texture.
    demo.gctx.releaseResource(demo.depth_texture_view);
    demo.gctx.destroyResource(demo.depth_texture);

    // Create a new depth texture to match the new window size.
    const depth = Wgpu.createDepthTexture(demo.gctx);
    demo.depth_texture = depth.texture;
    demo.depth_texture_view = depth.view;
}

pub fn updateAspectRatio(demo: *DemoState) void {
    updateDepthTexture(demo);
    const consumer_waiting = demo.buffers.data.consumers.mapping.waiting;
    const producer_waiting = demo.buffers.data.producers.mapping.waiting;
    if (consumer_waiting or producer_waiting) {
        demo.push_coord_update = true;
        return;
    }
    Wgpu.updateCoords(demo.gctx, Consumer, demo.buffers.data.consumers);
    Wgpu.updateCoords(demo.gctx, Producer, demo.buffers.data.producers);
    demo.push_coord_update = false;
    demo.params.aspect = Camera.getAspectRatio(demo.gctx);
}

fn getContentScale(window: *zglfw.Window) f32 {
    const content_scale = window.getContentScale();
    return @max(content_scale[0], content_scale[1]);
}

fn setImguiContentScale(scale: f32) void {
    zgui.getStyle().* = zgui.Style.init();
    zgui.getStyle().scaleAllSizes(scale);
}

pub fn deinit(demo: *DemoState) void {
    demo.gctx.destroy(demo.allocator);
    demo.stats.deinit();
    demo.buffers.data.consumers.list.deinit();
    demo.buffers.data.producers.list.deinit();
    demo.buffers.data.stats.list.deinit();
    demo.* = undefined;
}

pub fn main() !void {
    try zglfw.init();
    defer zglfw.terminate();

    // Change current working directory to where the executable is located.
    var buffer: [1024]u8 = undefined;
    const path = std.fs.selfExeDirPath(buffer[0..]) catch ".";
    std.posix.chdir(path) catch {};

    zglfw.windowHintTyped(.client_api, .no_api);

    const window = try zglfw.Window.create(1600, 1000, "Simulations", null);
    defer window.destroy();
    window.setSizeLimits(400, 400, -1, -1);
    window.setPos(0, 0);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    zstbi.init(allocator);
    defer zstbi.deinit();

    var demo = try init(allocator, window);
    defer deinit(&demo);

    Statistics.setNum(&demo, demo.params.num_consumers, .consumers);
    Statistics.setNum(&demo, demo.params.num_producers, .producers);
    Consumer.generateFromParams(&demo);
    Producer.generateBulk(&demo, demo.params.num_producers);

    zgui.init(allocator);
    defer zgui.deinit();
    zgui.plot.init();
    defer zgui.plot.deinit();

    zgui.io.setIniFilename(null);

    _ = zgui.io.addFontFromFile(
        "content/fonts/Roboto-Medium.ttf",
        26.0 * demo.content_scale,
    );
    setImguiContentScale(demo.content_scale);

    zgui.backend.init(
        window,
        demo.gctx.device,
        @intFromEnum(zgpu.GraphicsContext.swapchain_format),
        @intFromEnum(wgpu.TextureFormat.undef),
    );
    defer zgui.backend.deinit();

    zgui.plot.getStyle().plot_padding = .{ 20, 20 };

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        zglfw.pollEvents();
        update(&demo);
        draw(&demo);
    }
}
