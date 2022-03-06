const std = @import("std");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");

const GraphicsContext = @import("graphics_context.zig").GraphicsContext;
const Image = @import("graphics_context.zig").Image;
const Swapchain = @import("swapchain.zig").Swapchain;
const resources = @import("resources");

const zal = @import("zalgebra");

const Self = @This();

gc: *GraphicsContext,
layout: vk.PipelineLayout,
pipeline: vk.Pipeline,

pub fn init(
    allocator: std.mem.Allocator,
    gc: *GraphicsContext,
    render_pass: vk.RenderPass,
    descriptor_set_layouts: []const vk.DescriptorSetLayout,
    push_constants: []const vk.PushConstantRange,
    vertex_shader: []const u8,
    fragment_shader: []const u8,
    vertex_input_bindings: []const vk.VertexInputBindingDescription,
    vertex_input_attributes: []const vk.VertexInputAttributeDescription,
) !Self {
    const layout = try gc.vkd.createPipelineLayout(gc.dev, &.{
        .flags = .{},
        .set_layout_count = @intCast(u32, descriptor_set_layouts.len),
        .p_set_layouts = @ptrCast([*]const vk.DescriptorSetLayout, descriptor_set_layouts.ptr),
        .push_constant_range_count = @intCast(u32, push_constants.len),
        .p_push_constant_ranges = @ptrCast([*]const vk.PushConstantRange, push_constants.ptr),
    }, null);
    errdefer gc.vkd.destroyPipelineLayout(gc.dev, layout, null);

    const vertex_mem = try allocator.alignedAlloc(u8, @alignOf(u32), vertex_shader.len);
    defer allocator.free(vertex_mem);
    std.mem.copy(u8, vertex_mem, vertex_shader);
    const vert = try gc.vkd.createShaderModule(gc.dev, &.{
        .flags = .{},
        .code_size = vertex_mem.len,
        .p_code = @ptrCast([*]const u32, vertex_mem.ptr),
    }, null);
    defer gc.vkd.destroyShaderModule(gc.dev, vert, null);

    const fragment_mem = try allocator.alignedAlloc(u8, @alignOf(u32), fragment_shader.len);
    defer allocator.free(fragment_mem);
    std.mem.copy(u8, fragment_mem, fragment_shader);
    const frag = try gc.vkd.createShaderModule(gc.dev, &.{
        .flags = .{},
        .code_size = fragment_mem.len,
        .p_code = @ptrCast([*]const u32, fragment_mem.ptr),
    }, null);
    defer gc.vkd.destroyShaderModule(gc.dev, frag, null);

    const pssci = [_]vk.PipelineShaderStageCreateInfo{
        .{
            .flags = .{},
            .stage = .{ .vertex_bit = true },
            .module = vert,
            .p_name = "main",
            .p_specialization_info = null,
        },
        .{
            .flags = .{},
            .stage = .{ .fragment_bit = true },
            .module = frag,
            .p_name = "main",
            .p_specialization_info = null,
        },
    };

    const pvisci = vk.PipelineVertexInputStateCreateInfo{
        .flags = .{},
        .vertex_binding_description_count = @intCast(u32, vertex_input_bindings.len),
        .p_vertex_binding_descriptions = @ptrCast([*]const vk.VertexInputBindingDescription, vertex_input_bindings.ptr),
        .vertex_attribute_description_count = @intCast(u32, vertex_input_attributes.len),
        .p_vertex_attribute_descriptions = @ptrCast([*]const vk.VertexInputAttributeDescription, vertex_input_attributes.ptr),
    };

    const piasci = vk.PipelineInputAssemblyStateCreateInfo{
        .flags = .{},
        .topology = .triangle_list,
        .primitive_restart_enable = vk.FALSE,
    };

    const pvsci = vk.PipelineViewportStateCreateInfo{
        .flags = .{},
        .viewport_count = 1,
        .p_viewports = undefined, // set in createCommandBuffers with cmdSetViewport
        .scissor_count = 1,
        .p_scissors = undefined, // set in createCommandBuffers with cmdSetScissor
    };

    const prsci = vk.PipelineRasterizationStateCreateInfo{
        .flags = .{},
        .depth_clamp_enable = vk.FALSE,
        .rasterizer_discard_enable = vk.FALSE,
        .polygon_mode = .fill,
        .cull_mode = .{ .back_bit = true },
        .front_face = .counter_clockwise,
        .depth_bias_enable = vk.FALSE,
        .depth_bias_constant_factor = 0,
        .depth_bias_clamp = 0,
        .depth_bias_slope_factor = 0,
        .line_width = 1,
    };

    const pmsci = vk.PipelineMultisampleStateCreateInfo{
        .flags = .{},
        .rasterization_samples = .{ .@"1_bit" = true },
        .sample_shading_enable = vk.FALSE,
        .min_sample_shading = 1,
        .p_sample_mask = null,
        .alpha_to_coverage_enable = vk.FALSE,
        .alpha_to_one_enable = vk.FALSE,
    };

    const pcbas = [_]vk.PipelineColorBlendAttachmentState{
        .{ // color image
            .blend_enable = vk.FALSE,
            .src_color_blend_factor = .one,
            .dst_color_blend_factor = .zero,
            .color_blend_op = .add,
            .src_alpha_blend_factor = .one,
            .dst_alpha_blend_factor = .zero,
            .alpha_blend_op = .add,
            .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
        },
        .{ // id image
            .blend_enable = vk.FALSE,
            .src_color_blend_factor = .one,
            .dst_color_blend_factor = .zero,
            .color_blend_op = .add,
            .src_alpha_blend_factor = .one,
            .dst_alpha_blend_factor = .zero,
            .alpha_blend_op = .add,
            .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
        },
    };

    const pcbsci = vk.PipelineColorBlendStateCreateInfo{
        .flags = .{},
        .logic_op_enable = vk.FALSE,
        .logic_op = .copy,
        .attachment_count = pcbas.len,
        .p_attachments = @ptrCast([*]const vk.PipelineColorBlendAttachmentState, &pcbas),
        .blend_constants = [_]f32{ 0, 0, 0, 0 },
    };

    const dynstate = [_]vk.DynamicState{ .viewport, .scissor };
    const pdsci = vk.PipelineDynamicStateCreateInfo{
        .flags = .{},
        .dynamic_state_count = dynstate.len,
        .p_dynamic_states = &dynstate,
    };

    const gpci = vk.GraphicsPipelineCreateInfo{
        .flags = .{},
        .stage_count = 2,
        .p_stages = &pssci,
        .p_vertex_input_state = &pvisci,
        .p_input_assembly_state = &piasci,
        .p_tessellation_state = null,
        .p_viewport_state = &pvsci,
        .p_rasterization_state = &prsci,
        .p_multisample_state = &pmsci,
        .p_depth_stencil_state = null,
        .p_color_blend_state = &pcbsci,
        .p_dynamic_state = &pdsci,
        .layout = layout,
        .render_pass = render_pass,
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };

    var pipeline: vk.Pipeline = undefined;
    _ = try gc.vkd.createGraphicsPipelines(
        gc.dev,
        .null_handle,
        1,
        @ptrCast([*]const vk.GraphicsPipelineCreateInfo, &gpci),
        null,
        @ptrCast([*]vk.Pipeline, &pipeline),
    );

    return Self{
        .gc = gc,
        .layout = layout,
        .pipeline = pipeline,
    };
}

pub fn deinit(self: *const Self) void {
    self.gc.vkd.destroyPipeline(self.gc.dev, self.pipeline, null);
    self.gc.vkd.destroyPipelineLayout(self.gc.dev, self.layout, null);
}
