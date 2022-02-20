const std = @import("std");

//const gl = @import("zgl");
const gl = @import("opengl/opengl.zig");
const imgui = @import("imgui.zig");
const imgui2 = @import("imgui2.zig");
const sdl = @import("sdl.zig");
const Details = @import("details_window.zig");

const EntityId = @import("entity.zig").EntityId;
const ComponentId = @import("entity.zig").ComponentId;
const World = @import("world.zig");
const EntityBuilder = @import("entity_builder.zig");
const Query = @import("query.zig").Query;
const Tag = @import("tag_component.zig").Tag;
const Commands = @import("commands.zig");

const Position = struct {
    position: [3]f32,
};
const Gravity = struct { uiae: i32 = 99 };
const A = struct { i: i64 };
const B = struct { b: bool, Gravity: Gravity = .{} };
const C = struct { i: i16 = 123, b: bool = true, u: u8 = 9 };
const D = struct {};

pub fn testSystem1(query: Query(.{ Tag, A })) !void {
    var iter = query.iter();
    while (iter.next()) |entity| {
        _ = entity;
    }
}

pub fn testSystem2(query: Query(.{ Tag, A, B })) !void {
    var iter = query.iter();
    while (iter.next()) |entity| {
        _ = entity;
    }
}

pub fn testSystem3(query: Query(.{ Tag, A, B, C })) !void {
    var iter = query.iter();
    while (iter.next()) |entity| {
        _ = entity;
    }
}

pub fn testSystem4(query: Query(.{ Tag, A, B, C, D })) !void {
    var iter = query.iter();
    while (iter.next()) |entity| {
        _ = entity;
    }
}

pub fn testSystem5(time: *const Time, query: Query(.{ Tag, B })) !void {
    _ = time;
    var iter = query.iter();
    while (iter.next()) |entity| {
        _ = entity;
    }
}

const Time = struct {
    delta: f64 = 0,
    now: f64 = 0,
};

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // init SDL
    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != 0) {
        sdl.SDL_Log("Unable to initialize SDL: %s", sdl.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer sdl.SDL_Quit();

    // create window
    var window = try sdl.Window.init();
    defer window.deinit();
    window.makeContextCurrent();
    try gl.load_gl();

    // init imgui
    _ = imgui.CreateContext();
    var io = imgui.GetIO();
    io.ConfigFlags = io.ConfigFlags.with(.{ .DockingEnable = true, .ViewportsEnable = true });
    _ = imgui2.ImGui_ImplSDL2_InitForOpenGL(window.handle, true);
    defer imgui2.ImGui_ImplSDL2_Shutdown();
    _ = imgui2.ImGui_ImplOpenGL3_Init("#version 130");
    defer imgui2.ImGui_ImplOpenGL3_Shutdown();

    var world = try World.init(allocator);
    defer world.deinit();
    defer world.dumpGraph() catch {};

    // _ = try EntityBuilder.initWithTag(world, "Foo")
    //     .addComponent(A{ .i = 1 })
    //     .build();

    // _ = try EntityBuilder.initWithTag(world, "Foo2")
    //     .addComponent(A{ .i = 2 })
    //     .build();

    // _ = try EntityBuilder.initWithTag(world, "Bar")
    //     .addComponent(A{ .i = 11 })
    //     .addComponent(B{ .b = false })
    //     .build();

    // _ = try EntityBuilder.initWithTag(world, "Bar2")
    //     .addComponent(A{ .i = 12 })
    //     .addComponent(B{ .b = true })
    //     .build();

    // _ = try EntityBuilder.initWithTag(world, "Bar3")
    //     .addComponent(B{ .b = false })
    //     .addComponent(A{ .i = 13 })
    //     .build();

    // _ = try EntityBuilder.initWithTag(world, "Baz")
    //     .addComponent(B{ .b = true })
    //     .addComponent(C{})
    //     .addComponent(A{ .i = 21 })
    //     .build();

    // _ = try EntityBuilder.initWithTag(world, "Baz2")
    //     .addComponent(A{ .i = 22 })
    //     .addComponent(C{ .i = 420, .u = 69 })
    //     .addComponent(B{ .b = false })
    //     .build();

    // _ = try EntityBuilder.initWithTag(world, "Tog")
    //     .addComponent(C{ .i = 69 })
    //     .addComponent(B{ .b = true })
    //     .addComponent(A{ .i = 31 })
    //     .addComponent(D{})
    //     .build();

    try world.addSystem(testSystem1, "{A}");
    try world.addSystem(testSystem2, "{A, B}");
    try world.addSystem(testSystem3, "{A, B, C}");
    try world.addSystem(testSystem4, "{A, B, C, D}");
    try world.addSystem(testSystem5, "{B}");

    _ = try world.addResource(Time{});
    var commands = try world.addResource(Commands.init(allocator));
    defer commands.deinit();

    const e = try commands.createEntity();
    _ = try commands.addComponent(e, Tag{ .name = "e" });
    _ = try commands.addComponent(e, C{ .i = 69 });
    _ = try commands.addComponent(e, B{ .b = false });
    _ = try commands.addComponent(e, A{ .i = 31 });
    _ = try commands.addComponent(e, D{});
    _ = try commands.applyCommands(world);

    var details = Details.init(allocator);

    var show_demo_window = true;

    // Wait for the user to close the window.
    std.debug.print("\n==============================================================================================================================================\n", .{});
    var quit = false;

    var selectedEntity: EntityId = 0;

    var lastFrameTime = std.time.nanoTimestamp();
    var frameTimeSmoothed: f64 = 0;
    while (!quit) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            _ = imgui2.ImGui_ImplSDL2_ProcessEvent(event);
            switch (event.@"type") {
                sdl.SDL_QUIT => {
                    quit = true;
                },
                else => {},
            }
        }

        const currentFrameTime = std.time.nanoTimestamp();
        const frameTimeNs = currentFrameTime - lastFrameTime;
        const frameTime = (@intToFloat(f64, frameTimeNs) / std.time.ns_per_ms);
        frameTimeSmoothed = (0.9 * frameTimeSmoothed) + (0.1 * frameTime);
        lastFrameTime = currentFrameTime;
        var fps: f64 = blk: {
            if (frameTimeSmoothed == 0) {
                break :blk -1;
            } else {
                break :blk (1000.0 / frameTimeSmoothed);
            }
        };

        var timeResource = try world.getResource(Time);
        timeResource.delta = @intToFloat(f64, frameTimeNs) / std.time.ns_per_s;
        timeResource.now += timeResource.delta;

        imgui2.newFrame();
        imgui2.dockspace();

        if (show_demo_window) {
            imgui2.showDemoWindow(&show_demo_window);
        }

        if (imgui.Begin("Stats")) {
            imgui.LabelText("Frame time: ", "%.2f", frameTimeSmoothed);
            imgui.LabelText("FPS: ", "%.1f", fps);
        }
        imgui.End();

        if (imgui.Begin("Entities")) {
            if (imgui.Button("Create Entity")) {
                const entt = try commands.createEntity();
                _ = entt;
                // _ = try commands.addComponent(e, Tag{ .name = "e" });
            }

            var tableFlags = imgui.TableFlags{
                .Resizable = true,
                .RowBg = true,
                .Sortable = true,
            };
            tableFlags = tableFlags.with(imgui.TableFlags.Borders);
            if (imgui.BeginTable("Entities", 4, tableFlags, .{}, 0)) {
                defer imgui.EndTable();

                var entityIter = world.entities.iterator();
                while (entityIter.next()) |entry| {
                    const entityId = entry.key_ptr.*;
                    imgui.PushIDInt64(entityId);
                    defer imgui.PopID();

                    imgui.TableNextRow(.{}, 0);
                    _ = imgui.TableSetColumnIndex(0);
                    imgui.Text("%d", entityId);

                    _ = imgui.TableSetColumnIndex(1);
                    if (try world.getComponent(entityId, Tag)) |tag| {
                        imgui.Text("%.*s", tag.name.len, tag.name.ptr);
                    }

                    _ = imgui.TableSetColumnIndex(2);
                    if (imgui.Button("Select")) {
                        // const entt = try commands.getEntity(entityId);
                        // _ = try commands.addComponent(entt, Tag{ .name = "lol" });
                        selectedEntity = entityId;
                    }

                    _ = imgui.TableSetColumnIndex(3);
                    if (imgui.Button("Destroy")) {
                        try commands.destroyEntity(entityId);
                    }
                }
            }
        }
        imgui.End();

        try details.draw(world, selectedEntity);

        try world.runFrameSystems();

        imgui2.endFrame();

        try commands.applyCommands(world);

        imgui2.render();

        // gl.viewport(0, 0, @floatToInt(c_int, io.DisplaySize.x), @floatToInt(c_int, io.DisplaySize.y));
        // gl.clearColor(1, 0, 1, 1);
        // gl.clear(gl.COLOR_BUFFER_BIT);

        imgui2.ImGui_ImplOpenGL3_RenderDrawData(imgui2.getDrawData());
        imgui2.updatePlatformWindows();

        window.swapBuffers();
    }

    std.debug.print("\n==============================================================================================================================================\n", .{});

    world.dump();

    // if (world.getArchetypeTable(try world.createArchetypeStruct(.{ Tag, B }))) |table| {
    //     std.log.info("Found table {}", .{table});
    //     var x = table.getTyped(.{ Tag, B });
    //     std.log.info("{}", .{x});

    //     std.log.info("B", .{});
    //     for (x.B) |*a, i| {
    //         std.log.info("[{}] {}", .{ i, a.* });
    //     }
    // }
    // if (world.getArchetypeTable(try world.createArchetypeStruct(.{ Tag, A, B }))) |table| {
    //     std.log.info("Found table {}", .{table});
    //     var x = table.getTyped(.{ Tag, A, B });
    //     std.log.info("{}", .{x});

    //     std.log.info("A", .{});
    //     for (x.A) |*a, i| {
    //         std.log.info("[{}] {}", .{ i, a.* });
    //     }

    //     std.log.info("B", .{});
    //     for (x.B) |*a, i| {
    //         std.log.info("[{}] {}", .{ i, a.* });
    //     }
    // }

    // var i: u64 = 0;
    // while (i < 100) : (i += 1) {
    //     const entity = try world.createEntity();
    //     try world.addComponent(entity.id, A{});

    //     const entity2 = try world.createEntity();
    //     try world.addComponent(entity2.id, A{});
    //     try world.addComponent(entity2.id, B{});

    //     const entity3 = try world.createEntity();
    //     try world.addComponent(entity3.id, C{});
    //     try world.addComponent(entity3.id, B{});
    //     try world.addComponent(entity3.id, A{});

    //     const entity4 = try world.createEntity();
    //     try world.addComponent(entity4.id, B{});
    //     try world.addComponent(entity4.id, D{});
    //     try world.addComponent(entity4.id, A{});
    //     try world.addComponent(entity4.id, C{});
    // }
    // world.dump();

    // const entity = try world.createEntity();
    // world.dump();
    // try world.addComponent(entity.id, Position{ .position = .{ 1, 2, 3 } });
    // world.dump();
    // try world.addComponent(entity.id, Gravity{});
    // world.dump();

    // const entity2 = try world.createEntity();
    // world.dump();
    // try world.addComponent(entity2.id, Position{ .position = .{ 4, 5, 6 } });
    // world.dump();
    // try world.addComponent(entity2.id, Gravity{});
    // world.dump();
    // try world.addComponent(entity2.id, 5);
    // world.dump();
    // try world.addComponent(entity2.id, true);
    // world.dump();

    // try world.addComponent(entity.id, false);
    // world.dump();
    // try world.addComponent(entity.id, 69);
    // world.dump();

    // try world.addComponent(entity2.id, @intCast(u8, 5));
    // world.dump();

    // world.dump();
}
