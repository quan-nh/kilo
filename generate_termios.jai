#import "Basic";
#import "Bindings_Generator";
#import "Compiler";
#import "File";
#import "String";

#run {
    set_build_options_dc(.{do_output=false});
    if !generate_termios_bindings() {
        compiler_set_workspace_status(.FAILED);
    }
}

generate_termios_bindings :: () -> bool {
    options: Generate_Bindings_Options;

    #if OS == .MACOS {
        sdk_path := "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk";
        array_add(*options.source_files, tprint("%/usr/include/sys/termios.h", sdk_path));
        array_add(*options.extra_clang_arguments, "-isysroot", sdk_path);
        array_add(*options.system_library_names, "libc");
    } else #if OS == .LINUX {
        array_add(*options.source_files, "/usr/include/termios.h");
        array_add(*options.system_library_names, "libc");
    }

    array_add(*options.system_types_to_include, "termios");
    array_add(*options.path_fragments_to_treat_as_non_system_paths, "termios.h");

    options.visitor = (decl: *Declaration, parent_decl: *Declaration) -> Declaration_Visit_Result {
        if !parent_decl {
            if decl.name == "tcgetattr" || decl.name == "tcsetattr" || decl.name == "termios" ||
               decl.name == "ECHO" || decl.name == "TCSAFLUSH" ||
               decl.name == "cc_t" || decl.name == "speed_t" || decl.name == "tcflag_t" ||
               decl.name == "NCCS" {
                return .RECURSE;
            }
            return .STOP;
        }
        return .RECURSE;
    };

    output_path := "termios_bindings.jai";
    return generate_bindings(options, output_path);
}

main :: () {}
