module opl2_clk (
    input  wire clk, // 28 MHz
    input  wire reset, 
    output reg clk_en // 3.579545 MHz
);

    reg [15:0] accumulator;
	 localparam [15:0] FTW = 16'd8378;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            accumulator <= 16'h0;
				clk_en <= 0;
        end else begin
            {clk_en, accumulator} <= accumulator + FTW;
        end
    end

endmodule
