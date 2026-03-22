/*
How to get information about a directory, including which files and directories
it contains.
*/
package dir_info

import "core:fmt"
import "core:os"

main :: proc() {
	cwd, wd_err := os.get_working_directory(context.allocator)
	if wd_err != nil {
		fmt.eprintfln("Could not get working directory: %v", wd_err)
		os.exit(1)
	}
	defer delete(cwd)

	// Swap `cwd` for some other string to change which folder you're looking at
	f, open_err := os.open(cwd)
	if open_err != nil {
		fmt.eprintfln("Could not open directory for reading: %v", open_err)
		os.exit(1)
	}
	defer os.close(f)

	/*
	File_Info :: struct {
		fullpath:          string,        // fullpath of the file
		name:              string,        // base name of the file

		inode:             u128,          // might be zero if cannot be determined
		size:              i64 `fmt:"M"`, // length in bytes for regular files; system-dependent for other file types
		mode:              Permissions,   // file permission flags
		type:              File_Type,

		creation_time:     time.Time,
		modification_time: time.Time,
		access_time:       time.Time,
	}

	(from <odin>/core/os/stat.odin)
	*/
	fis: []os.File_Info

	/*
	This will deallocate `fis` at the end of this scope.

	It's not allocated yet, but `fis` is assigned a return value from
	`os.read_dir`. That's a	dynamically allocated slice.
	
	It doesn't matter that `fis` hasn't been assigned yet: `defer` will fetch
	the variable `fis` at the end of this scope. It does not fetch the value of
	that variable now.

	Note that each `File_Info` contains an allocated `fullpath` field. That's
	why this uses `os.file_info_slice_delete(fis)` instead of `delete(fis)`:
	It needs to go through the slice and deallocate those strings.
	*/
	defer os.file_info_slice_delete(fis, context.allocator)

	read_err: os.Error
	fis, read_err = os.read_dir(f, -1, context.allocator) // -1 reads all file infos
	if read_err != nil {
		fmt.eprintfln("Could not read directory: %v", read_err)
		os.exit(2)
	}

	fmt.printfln("Current working directory %v contains:", cwd)

	for fi in fis {
		if fi.type == .Directory {
			fmt.printfln("%v (directory)", fi.name)
		} else {
			fmt.printfln("%v (%M)", fi.name, fi.size)
		}
	}
}
