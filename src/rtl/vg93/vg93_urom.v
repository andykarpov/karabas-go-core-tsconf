// Thanks to deathsoft for the transistor-level schematic of the chip and to dr.Titus for the gate-level RTL.
//
// Microcode store: the ROM in block RAM, read with the address of the coming word at the word end (REG_MCMD
// takes it there, as on the chip). The image is docs/microcode/vg93-microcode-rom.hex (the simulation scripts copy
// it next to the model, Quartus reads it from the project directory).
// rtl_epm570/rtl/vg93_urom.v replaces this module in the MAX II build: the re-encoded program in the UFM, read
// serially after the word end (fetching meanwhile; keep spares a read).
module vg93_urom (
    input  wire sysclk,
    input  wire word_ends,
    input  wire [7:0] addr,               // address of the coming word (taken at word_ends)
    input  wire [7:0] pc,                 // address of the current word
    input  wire keep,                     // this word end keeps PC and the word
    output reg  [18:0] mword = 19'd0,     // the current microword (REG_MCMD)
    output wire fetching                  // the word is not yet there: never
);
`ifndef VG93_ROM_FILE
`define VG93_ROM_FILE "vg93-microcode-rom.hex"
`endif
    reg [18:0] rom [0:255];
    initial $readmemh(`VG93_ROM_FILE, rom);
    always @(posedge sysclk)
        if (word_ends) mword <= rom[addr];
    assign fetching = 1'b0;
endmodule
