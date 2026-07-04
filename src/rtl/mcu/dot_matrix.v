module dot_matrix(
    input wire clk,
    input wire reset,

    input wire signed [15:0] audio_l,
    input wire signed [15:0] audio_r,

    input wire iowr,
    input wire [15:0] ioa,
    input wire [7:0] iod,

    output wire cmd_wr,
    output wire [23:0] cmd    
);

wire audio_peaks_l_wr, audio_peaks_r_wr;
wire [15:0] audio_peaks_l, audio_peaks_r;
audio_peaks_writer audio_peaks_writer(
    .clk(clk),
    .reset(reset),
    .audio_l(audio_l),
    .audio_r(audio_r),
    .audio_peaks_l_wr(audio_peaks_l_wr),
    .audio_peaks_l(audio_peaks_l),
    .audio_peaks_r_wr(audio_peaks_r_wr),
    .audio_peaks_r(audio_peaks_r)
);

wire matrix_ctl_wr, matrix_pix_wr;
wire [7:0] matrix_ctl;
wire [15:0] matrix_pix;
dot_matrix_writer dot_matrix_wtiter(
    .clk(clk),
    .reset(reset),
    .iowr(iowr),
    .ioa(ioa),
    .iod(iod),
    .matrix_ctl(matrix_ctl),
    .matrix_ctl_wr(matrix_ctl_wr),
    .matrix_pix(matrix_pix),
    .matrix_pix_wr(matrix_pix_wr)
);

localparam [7:0] CMD_MATRIX_CTL  = 8'h60;
localparam [7:0] CMD_MATRIX_PIX  = 8'h61;
localparam [7:0] CMD_AUDIO_PEAKS_L = 8'h70;
localparam [7:0] CMD_AUDIO_PEAKS_R = 8'h71;

assign cmd_wr = (matrix_ctl_wr | matrix_pix_wr | audio_peaks_l_wr | audio_peaks_r_wr);
assign cmd = matrix_ctl_wr ? {CMD_MATRIX_CTL, 8'h00, matrix_ctl} :
             matrix_pix_wr ? {CMD_MATRIX_PIX, matrix_pix} : 
             audio_peaks_l_wr ? {CMD_AUDIO_PEAKS_L, audio_peaks_l} : 
             audio_peaks_r_wr ? {CMD_AUDIO_PEAKS_R, audio_peaks_r} : 
             24'h000000;

endmodule

///////////////////////////////////////////////////////////////////////////////////////////

module audio_peaks_writer(
    input wire clk,
    input wire reset,

    input wire signed [15:0] audio_l,
    input wire signed [15:0] audio_r,

    output reg audio_peaks_l_wr,
    output reg [15:0] audio_peaks_l,    
    output reg audio_peaks_r_wr,
    output reg [15:0] audio_peaks_r    
);

    wire [15:0] audio_abs_l, audio_abs_r;
    audio_abs_level audio_abs_level_l(.clk(clk), .audio_sample(audio_l), .audio_abs(audio_abs_l));
    audio_abs_level audio_abs_level_r(.clk(clk), .audio_sample(audio_r), .audio_abs(audio_abs_r));

    reg [20:0] audio_peaks_cnt;

    always @(posedge clk) begin
        audio_peaks_l_wr <= 0;
        audio_peaks_r_wr <= 0;
        
        if (audio_peaks_cnt >= 560002) begin
            audio_peaks_cnt <= 0;
            audio_peaks_l <= 0;
            audio_peaks_r <= 0;
        end else begin
            if (audio_abs_l > audio_peaks_l) audio_peaks_l <= audio_abs_l;
            if (audio_abs_r > audio_peaks_r) audio_peaks_r <= audio_abs_r;
            if (audio_peaks_cnt == 560000) audio_peaks_l_wr <= 1;
            if (audio_peaks_cnt == 560001) audio_peaks_r_wr <= 1;
            audio_peaks_cnt <= audio_peaks_cnt + 1;
        end
    end
endmodule

///////////////////////////////////////////////////////////////////////////////////////////

module audio_abs_level (
	input wire clk,
	input wire signed [15:0] audio_sample,
	output reg [15:0] audio_abs
);

// absolute value 0..65535
always @(posedge clk) begin
	if (audio_sample < 0)
		audio_abs <= -audio_sample;
	else 
		audio_abs <= audio_sample;
end

endmodule

///////////////////////////////////////////////////////////////////////////////////////////

module dot_matrix_writer(
    input wire clk,
    input wire reset,
    
    input wire iowr,
    input wire [15:0] ioa,
    input wire [7:0] iod,

    output reg matrix_ctl_wr,
    output reg [7:0] matrix_ctl,
    output reg matrix_pix_wr,
    output reg [15:0] matrix_pix
);

// zxuno ports
// #FC3B - adr
// -- F0 - matrix ctl
// -- F1 - matrix xy
// -- F2 - matrix color
// #FD3B - data
wire zxuno_reg_port = iowr & ioa[15:0] == 16'hFC3B;
wire zxuno_data_port = iowr & ioa[15:0] == 16'hFD3B;
reg [7:0] zxuno_reg;
always @(posedge clk or posedge reset) begin
    if (reset)
        zxuno_reg <= 8'hFF;
	else if (zxuno_reg_port)
		zxuno_reg <= iod;
end

// dot matrix regs & control signals
wire matrix_ctl_port = zxuno_data_port & zxuno_reg == 8'hF0;
wire matrix_xy_port = zxuno_data_port & zxuno_reg == 8'hF1;
wire matrix_color_port = zxuno_data_port & zxuno_reg == 8'hF2;
reg [7:0] matrix_xy;
reg matrix_ctl_prev, matrix_xy_prev, matrix_color_prev;
always @(posedge clk or posedge reset) begin
    if (reset) begin
        matrix_ctl_wr <= 0;
        matrix_pix_wr <= 0;
        matrix_ctl <= 8'h00;
        matrix_pix <= 16'h0000;
    end
    else begin        
	    matrix_ctl_prev <= matrix_ctl_port;
	    matrix_xy_prev <= matrix_xy_port;
	    matrix_color_prev <= matrix_color_port;
	    matrix_ctl_wr <= 0;
	    matrix_pix_wr <= 0;
	    if (matrix_ctl_port) begin
		    matrix_ctl <= iod;
		    if (~matrix_ctl_prev)
			    matrix_ctl_wr <= 1;
	    end
	    if (matrix_xy_port) begin
		    matrix_xy <= iod;
	    end
	    if (matrix_color_port) begin
		    matrix_pix <= {matrix_xy, iod};
		    if (~matrix_color_prev)
			    matrix_pix_wr <= 1;
	    end
    end
end

endmodule

