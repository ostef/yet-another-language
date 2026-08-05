// Tracy v0.13.1
// Based on modules/Iprof, but adapted for the Tracy profiler

#module_parameters(Import_Mode := ImportMode.Metaprogram)(Enabled := true) {
    ImportMode :: enum u8 {
        Metaprogram;
        Client;
    }
}

#if Import_Mode == .Metaprogram {
    // When being imported by a metaprogram, we provide code for instrumenting the
    // target program, including the Metaprogram_Plugin interface.

    #load "plugin.jai";
} else {
    #load "runtime.jai";
}
