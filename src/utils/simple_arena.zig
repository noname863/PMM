const std = @import("std");

pub fn SimpleArena(comptime batch_size: usize) type
{
    const ArenaList = std.SinglyLinkedList(usize);
    const ArenaNode = ArenaList.Node;

    const ArenaPrivate = struct
    {
        fn alignPtr(ptr: [*]u8, alignment: std.mem.Alignment) [*]u8
        {
            return @ptrFromInt(std.mem.alignForwardLog2(
                @intFromPtr(ptr + @sizeOf(ArenaNode)), @intFromEnum(alignment)));
        }

        fn deinitNode(node: *ArenaNode) void
        {
            var slice: []u8 = undefined;
            slice.ptr = @ptrCast(node);
            slice.len = node.data;
            std.heap.page_allocator.rawFree(slice, .fromByteUnits(@alignOf(ArenaNode)), @returnAddress());
        }
    };
    
    comptime
    {
        if (batch_size < @sizeOf(std.SinglyLinkedList(void).Node))
        {
            @compileError("Error: batch_size for arena is smaller than size of node to store the batch!");
        }
    }
    return struct {
        const Self = @This();
    
        buffer_list: ArenaList = .{},

        // includes sizeOf(ArenaNode)
        current_size: usize = 0,

        pub fn init() Self
        {
            return Self{
                .buffer_list = .{},
                .current_size = 0
            };
        }

        pub fn deinit(self: Self) void
        {
            var opt_node: ?*ArenaNode = self.buffer_list.first;
            while (opt_node) |node|
            {
                opt_node = node.next;
                ArenaPrivate.deinitNode(node);
            }
        }

        fn allocateNode(self: *Self, alloc_size: usize) ?[*]u8
        {
            const ptr: [*]u8 = std.heap.page_allocator.rawAlloc(alloc_size,
                .fromByteUnits(@alignOf(ArenaNode)), 0) orelse return null;
            const node: *ArenaNode = @ptrCast(@alignCast(ptr));
            node.data = alloc_size;
            self.buffer_list.prepend(node);

            return ptr;
        }

        fn allocateWithNewNode(self: *Self, len: usize, alignment: std.mem.Alignment) ?[*]u8
        {
            const align_bytes = alignment.toByteUnits();
            const alloc_size: usize = @max(batch_size, len + @sizeOf(ArenaNode) + align_bytes);
            const ptr = self.allocateNode(alloc_size) orelse return null;

            const aligned_ptr: [*]u8 = ArenaPrivate.alignPtr(ptr + @sizeOf(ArenaNode), alignment);
            self.current_size = len + (aligned_ptr - ptr);
            return aligned_ptr;
        }

        fn alloc(a: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8
        {
            _ = ret_addr;
            var self: *Self = @ptrCast(@alignCast(a));
            if (self.buffer_list.first) |node|
            {
                // TODO: for certain there is an error somewhere
                const node_ptr: [*]u8 = @ptrCast(node);
                const aligned_ptr: [*]u8 = ArenaPrivate.alignPtr(node_ptr + self.current_size, alignment);
                const free_mem: usize = node.data - (aligned_ptr - node_ptr);
                if (len < free_mem)
                {
                    self.current_size = (aligned_ptr - node_ptr) + len;
                    return aligned_ptr;
                }
                else
                {
                    return self.allocateWithNewNode(len, alignment);
                }
            }
            else
            {
                return self.allocateWithNewNode(len, alignment);
            }
        }

        const ResizeState = enum
        {
            NoNodes,
            WrongAllocation,
            Success,
            Failed
        };

        fn resizeWithState(self: *Self, mem: []u8, new_len: usize) ResizeState
        {
            if (self.buffer_list.first) |node|
            {
                const nodePtr: [*]u8 = @ptrCast(node);
                if ((mem.ptr - nodePtr) != self.current_size - mem.len)
                {
                    return ResizeState.WrongAllocation;
                }
                if (new_len < mem.len)
                {
                    self.current_size -= (mem.len - new_len);
                    return ResizeState.Success;
                }
                const free_mem: usize = node.data - (self.current_size);
                if (new_len - mem.len < free_mem)
                {
                    self.current_size += new_len - mem.len;
                    return ResizeState.Success;
                }
                else
                {
                    return ResizeState.Failed;
                }
            }
            return ResizeState.NoNodes;
        }

        fn resize(a: *anyopaque, mem: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool
        {
            _ = ret_addr;
            _ = alignment;
            const self: *Self = @ptrCast(@alignCast(a));
            return switch (resizeWithState(self, mem, new_len))
            {
                .NoNodes => false,
                .WrongAllocation => false,
                .Success => true,
                .Failed => false,
            };
        }

        fn remap(a: *anyopaque, mem: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8
        {
            _ = ret_addr;
            var self: *Self = @ptrCast(@alignCast(a));
            switch (resizeWithState(self, mem, new_len))
            {
                .NoNodes => { return null; },
                .WrongAllocation => { return null; },
                .Success => { return mem.ptr; },
                .Failed => {
                    const node = self.buffer_list.first.?;
                    const node_ptr: [*]u8 = @ptrCast(node);
                    const aligned_ptr: [*]u8 = ArenaPrivate.alignPtr(node_ptr + @sizeOf(ArenaNode), alignment);

                    // so, the only thing we can do in remap, is check that last allocation mmapped new node,
                    // and if it is true, create new node, move data there, and delete last one.
                    //
                    // If new allocation fits in new node, we would return in Success branch above,
                    // if new allocation want't last, we would return in WrongAllocation branch.
                    // Since mem was allocated by last allocation, and mem.ptr is in the beginning of
                    // node, that means only that allocation is in that node, and we can reallocate it
                    // if we want
                    if (aligned_ptr == mem.ptr)
                    {
                        _ = self.buffer_list.popFirst();

                        const node_len = new_len + @sizeOf(ArenaNode) + alignment.toByteUnits();
                        const new_ptr = self.allocateNode(node_len) orelse return null;

                        const new_aligned_ptr: [*]u8 = ArenaPrivate.alignPtr(new_ptr + @sizeOf(ArenaNode), alignment);
                        std.mem.copyForwards(u8, new_aligned_ptr[0..mem.len], mem);

                        std.heap.page_allocator.rawFree(node_ptr[0..node.data], .fromByteUnits(@alignOf(ArenaNode)), 0);

                        self.buffer_list.prepend(@ptrCast(@alignCast(new_ptr)));

                        return new_aligned_ptr;
                    }
                    else
                    {
                        return null;
                    }
                },
            }
        }

        fn free(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize) void
        {
            // noop
        }

        
        pub fn allocator(self: *Self) std.mem.Allocator
        {
            return std.mem.Allocator {
                .ptr = self,
                .vtable = &.{
                    .alloc = Self.alloc,
                    .resize = Self.resize,
                    .remap = Self.remap,
                    .free = Self.free,
                }
            };
        }

    };
}

