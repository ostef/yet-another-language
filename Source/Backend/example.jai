EmitAddAddMulProcedure :: (builder : *IRBuilder)
{
    proc := CreateIRProcedure (builder.module, "AddAddMul", .[g_ir_type_f32, g_ir_type_f32, g_ir_type_f32], g_ir_type_f32);

    proc.entry_block = CreateIRBasicBlock (proc, "Entry");
    ScopeBasicBlock (builder, proc.entry_block);

    a := GetParam (proc, 0);
    b := GetParam (proc, 1);
    c := GetParam (proc, 2);

    ab := EmitAdd (builder, a, b, "ab");
    bc := EmitAdd (builder, b, c, "bc");
    abbc := EmitMul (builder, ab, bc, "abbc");
    EmitReturn (builder, abbc);
}

main :: ()
{
    builder : IRBuilder;
    builder.module = CreateIRModule ();

    EmitAddAddMulProcedure (*builder);

    VerifyModule (builder.module);
}
