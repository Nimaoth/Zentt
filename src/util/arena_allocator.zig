const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = std.mem.Allocator;

/// This allocator takes an existing allocator, wraps it, and provides an interface
/// where you can allocate without freeing, and then free it all together.
pub const ClearableArenaAllocator = struct {
    child_allocator: Allocator,
    state: State,

    /// Inner state of ClearableArenaAllocator. Can be stored rather than the entire ClearableArenaAllocator
    /// as a memory-saving optimization.
    pub const State = struct {
        buffer_list: std.SinglyLinkedList([]u8) = @as(std.SinglyLinkedList([]u8), .{}),
        current: ?*BufNode = null,
        end_index: usize = 0,

        pub fn promote(self: State, child_allocator: Allocator) ClearableArenaAllocator {
            return .{
                .child_allocator = child_allocator,
                .state = self,
            };
        }
    };

    pub fn allocator(self: *ClearableArenaAllocator) Allocator {
        return Allocator.init(self, alloc, resize, free);
    }

    const BufNode = std.SinglyLinkedList([]u8).Node;

    pub fn init(child_allocator: Allocator) ClearableArenaAllocator {
        return (State{}).promote(child_allocator);
    }

    pub fn deinit(self: ClearableArenaAllocator) void {
        var it = self.state.buffer_list.first;
        while (it) |node| {
            // this has to occur before the free because the free frees node
            const next_it = node.next;
            self.child_allocator.free(node.data);
            it = next_it;
        }
    }

    /// Resets the arena allocator so that following allocations will start at the beginning of the arena again.
    /// Doesn't free any memory
    pub fn reset(self: *ClearableArenaAllocator) void {
        self.state.current = self.state.buffer_list.first;
        self.state.end_index = 0;
    }

    fn createNode(self: *ClearableArenaAllocator, prev_len: usize, minimum_size: usize) !*BufNode {
        std.debug.assert(self.state.current == null or self.state.current.?.next == null);
        const actual_min_size = minimum_size + (@sizeOf(BufNode) + 16);
        const big_enough_len = prev_len + actual_min_size;
        const len = big_enough_len + big_enough_len / 2;
        const buf = try self.child_allocator.rawAlloc(len, @alignOf(BufNode), 1, @returnAddress());
        const buf_node = @ptrCast(*BufNode, @alignCast(@alignOf(BufNode), buf.ptr));
        buf_node.* = BufNode{
            .data = buf,
            .next = null,
        };
        if (self.state.current) |current| {
            current.insertAfter(buf_node);
        } else {
            self.state.buffer_list.prepend(buf_node);
        }
        self.state.current = buf_node;
        self.state.end_index = 0;
        return buf_node;
    }

    fn alloc(self: *ClearableArenaAllocator, n: usize, ptr_align: u29, len_align: u29, ra: usize) ![]u8 {
        _ = len_align;
        _ = ra;

        var cur_node = if (self.state.current) |current| current else try self.createNode(0, n + ptr_align);
        while (true) {
            const cur_buf = cur_node.data[@sizeOf(BufNode)..];
            const addr = @ptrToInt(cur_buf.ptr) + self.state.end_index;
            const adjusted_addr = mem.alignForward(addr, ptr_align);
            const adjusted_index = self.state.end_index + (adjusted_addr - addr);
            const new_end_index = adjusted_index + n;

            if (new_end_index <= cur_buf.len) {
                const result = cur_buf[adjusted_index..new_end_index];
                self.state.end_index = new_end_index;
                return result;
            }

            const bigger_buf_size = @sizeOf(BufNode) + new_end_index;
            // Try to grow the buffer in-place
            cur_node.data = self.child_allocator.resize(cur_node.data, bigger_buf_size) orelse {
                if (cur_node.next) |next| {
                    cur_node = next;
                    self.state.current = cur_node;
                    self.state.end_index = 0;
                    continue;
                } else {
                    // Allocate a new node if that's not possible
                    cur_node = try self.createNode(cur_buf.len, n + ptr_align);
                    continue;
                }
            };
        }
    }

    fn resize(self: *ClearableArenaAllocator, buf: []u8, buf_align: u29, new_len: usize, len_align: u29, ret_addr: usize) ?usize {
        _ = buf_align;
        _ = len_align;
        _ = ret_addr;

        const cur_node = self.state.current orelse return null;
        const cur_buf = cur_node.data[@sizeOf(BufNode)..];
        if (@ptrToInt(cur_buf.ptr) + self.state.end_index != @ptrToInt(buf.ptr) + buf.len) {
            if (new_len > buf.len) return null;
            return new_len;
        }

        if (buf.len >= new_len) {
            self.state.end_index -= buf.len - new_len;
            return new_len;
        } else if (cur_buf.len - self.state.end_index >= new_len - buf.len) {
            self.state.end_index += new_len - buf.len;
            return new_len;
        } else {
            return null;
        }
    }

    fn free(self: *ClearableArenaAllocator, buf: []u8, buf_align: u29, ret_addr: usize) void {
        _ = buf_align;
        _ = ret_addr;

        const cur_node = self.state.current orelse return;
        const cur_buf = cur_node.data[@sizeOf(BufNode)..];

        if (@ptrToInt(cur_buf.ptr) + self.state.end_index == @ptrToInt(buf.ptr) + buf.len) {
            self.state.end_index -= buf.len;
        }
    }
};
