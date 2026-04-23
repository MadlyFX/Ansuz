package ansuz

import "base:runtime"

// --- Widget Identity ---

Widget_ID :: distinct u64

ID_NONE :: Widget_ID(0)

MAX_ID_STACK :: 64

ID_Stack :: struct {
	items: [MAX_ID_STACK]Widget_ID,
	count: int,
}

// FNV-1a hash constants
FNV_OFFSET :: u64(0xcbf29ce484222325)
FNV_PRIME  :: u64(0x100000001b3)

hash_bytes :: proc(data: []u8, seed: u64 = FNV_OFFSET) -> u64 {
	h := seed
	for b in data {
		h ~= u64(b)
		h *= FNV_PRIME
	}
	return h
}

hash_string :: proc(s: string, seed: u64 = FNV_OFFSET) -> u64 {
	return hash_bytes(transmute([]u8)s, seed)
}

hash_u64 :: proc(val: u64, seed: u64 = FNV_OFFSET) -> u64 {
	bytes := transmute([8]u8)val
	return hash_bytes(bytes[:], seed)
}

id_stack_top :: proc(stack: ^ID_Stack) -> u64 {
	if stack.count > 0 {
		return u64(stack.items[stack.count - 1])
	}
	return FNV_OFFSET
}

id_stack_push :: proc(stack: ^ID_Stack, id: Widget_ID) {
	assert(stack.count < MAX_ID_STACK, "ID stack overflow")
	stack.items[stack.count] = id
	stack.count += 1
}

id_stack_pop :: proc(stack: ^ID_Stack) {
	assert(stack.count > 0, "ID stack underflow")
	stack.count -= 1
}

id_from_string :: proc(stack: ^ID_Stack, label: string) -> Widget_ID {
	return Widget_ID(hash_string(label, id_stack_top(stack)))
}

id_from_ptr :: proc(stack: ^ID_Stack, ptr: rawptr) -> Widget_ID {
	return Widget_ID(hash_u64(u64(uintptr(ptr)), id_stack_top(stack)))
}

id_from_int :: proc(stack: ^ID_Stack, n: int) -> Widget_ID {
	return Widget_ID(hash_u64(u64(n), id_stack_top(stack)))
}

id_from_loc :: proc(stack: ^ID_Stack, loc: runtime.Source_Code_Location) -> Widget_ID {
	h := hash_string(loc.file_path, id_stack_top(stack))
	h = hash_u64(u64(loc.line), h)
	h = hash_u64(u64(loc.column), h)
	return Widget_ID(h)
}

id_from_ptr_loc :: proc(stack: ^ID_Stack, ptr: rawptr, loc: runtime.Source_Code_Location) -> Widget_ID {
	h := hash_u64(u64(uintptr(ptr)), id_stack_top(stack))
	h = hash_u64(u64(loc.line), h)
	h = hash_u64(u64(loc.column), h)
	return Widget_ID(h)
}
