// Thanks to deathsoft for the transistor-level schematic of the chip and to dr.Titus for the gate-level RTL.
//
// Down counter with load and shift (CNT1, CNT2, the step rate counter):
//   ena && sload: q <= d;  ena && shift: q <= q << 1;  ena: q <= q - 1.
// zero = (q == 0); in a shift word it shows !q[W-1] instead (the users never test it then). That is what a carry
// chain counter gives (zero = no carry out of q + all ones; a shift word computes q + q): rtl_epm570/rtl/vg93_dcnt.v
// is the same module on the MAX II carry chain, one LE per bit, and this plain version is its simulation model.
module vg93_dcnt #(parameter W = 8) (
    input  wire clk, ena, sload, shift,
    input  wire [W-1:0] d,
    output wire [W-1:0] q,
    output wire zero
);
    reg [W-1:0] r = {W{1'b0}};
    always @(posedge clk)
        if (ena) r <= sload ? d : shift ? {r[W-2:0], 1'b0} : r - 1'b1;
    assign q = r;
    assign zero = shift ? !r[W-1] : r == {W{1'b0}};
endmodule
