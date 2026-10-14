// Thanks to deathsoft for the transistor-level schematic of the chip and to titus for the gate-level RTL.
//
// Helpers shared by the blocks (included inside a module). Functions take every input as an argument: an assign
// with a function that read a global signal would not be re-evaluated when that signal changes.

// RS latch of the die, without priority: R = S = 1 keeps the value (on the chip the state is undefined, testing.md
// "Неопределённое поведение"; the C core keeps the value too).
function rs(input q, input r, input s);
    rs = (s && !r) ? 1'b1 : (r && !s) ? 1'b0 : q;
endfunction

// A register with two sources: sources that coincide (a host write during a shift) meet in a wired AND, as on the
// chip; with no source the register holds.
function [7:0] wired_and(input [7:0] hold, input a_en, input [7:0] a, input b_en, input [7:0] b);
    wired_and = (a_en ? a : 8'hFF) & (b_en ? b : 8'hFF) & ((a_en || b_en) ? 8'hFF : hold);
endfunction
