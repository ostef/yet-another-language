#scope_file

#import "Hash_Map";

g_record_allocations := true;
g_allocations_per_type : HashMap(*Type_Info, int);
g_allocations : HashMap(*void, RecordedAllocation);

#scope_export

InitAllocationRecording :: (allocator : Allocator) {
    g_allocations_per_type.allocator = allocator;
    g_allocations.allocator = allocator;
}

IsRecordingAllocations :: inline () -> bool {
    return g_record_allocations;
}

SetRecordingAllocations :: inline (enabled : bool) {
    g_record_allocations = enabled;
}

RecordAllocation :: inline (ptr : *void, type : *Type_Info, count : int) {
    if !type {
        return;
    }

    if g_record_allocations {
        g_record_allocations = false;

        alloc_count := HashMapInsert(*g_allocations_per_type, type);
        alloc_count.* += count;

        HashMapInsert(*g_allocations, ptr, .{type, count});

        g_record_allocations = true;
    }
}

RecordDeallocation :: inline (ptr : *void, allocator : Allocator) {
    // Ignore frees for temporary allocator
    if allocator.proc == Basic.temporary_allocator_proc {
        return;
    }

    found, alloc := HashMapRemove(*g_allocations, ptr);
    if !found {
        return;
    }

    count := HashMapGetPtr(*g_allocations_per_type, alloc.type);
    if count {
        count.* -= alloc.count;

        if count.* == 0 {
            HashMapRemove(*g_allocations_per_type, alloc.type);
        }
    }
}

RecordedAllocation :: struct {
    type : *Type_Info;
    count : int;
}

GetRecordedAllocations :: () -> []RecordedAllocation {
    prev_record_allocations := g_record_allocations;
    defer g_record_allocations = prev_record_allocations;
    g_record_allocations = false;

    allocs : [..]RecordedAllocation;
    ArrayReserve(*allocs, g_allocations_per_type.count);

    for count, type : g_allocations_per_type {
        ArrayPush(*allocs, .{type=type, count=count});
    }

    return allocs;
}
