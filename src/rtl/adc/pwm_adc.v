module pwm_adc(
    input wire clk,			// 128 x Fs
    input wire sdin,			// input from analog comparator
    output reg fb,			// Feedback to integrator
    output wire newsample,	// New output sample next clock pulse
    output reg [11:0]dout	// Output data
);

reg [18:0]inte1=0;		// Integrator registers
reg [18:0]inte2=0;
reg [18:0]inte3=0;
reg [18:0]diff1=0;		// differenciator registers
reg [18:0]diff2=0;
reg [18:0]diff3=0;
wire [18:0]add1 = (~fb) + inte1;	// Integrator adders
wire [18:0]add2 = add1 + inte2;
wire [18:0]add3 = add2 + inte3;

wire [18:0]sub1 = add3 - diff1;		// Differenciator subs
wire [18:0]sub2 = sub1 - diff2;
wire [18:0]sub3 = sub2 - diff3;

reg [5:0]deci=0;		// Decimator counter
assign newsample = &deci;	// new sample after maximal count

//reg [11:0]dout=0;		// Output register (12 bits, but only 10.4 effective bits)

always @(negedge clk) begin
    fb <= ~sdin;		// Negative feedback loop
    deci <= deci + 1;	// decimator counter
    inte1 <= add1;		// Integrators
    inte2 <= add2;
    inte3 <= add3;
    if (newsample) begin	// every 128 cycles
	diff1 <= add3;	// Differenciators
	diff2 <= sub1;
	diff3 <= sub2;
	// Output with saturation
	dout <= sub3[18] ? 12'hfff : sub3[17:6];
    end
end

endmodule
