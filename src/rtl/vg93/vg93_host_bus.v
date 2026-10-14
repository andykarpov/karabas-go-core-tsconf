// Thanks to deathsoft for the transistor-level schematic of the chip and to titus for the gate-level RTL.
//
// Host bus interface (sheets io_ports, addr_decoder, reg_read_logic, the write captures of cmd_reg, trk_reg,
// sect_reg, data_reg).
//
// Read: DAL is driven straight from the pins' /RE & /CS with the register A1 A0 selects (status, TRK, SEC, DATA as
// the host sees them). Write: REG_DAL_IN follows DAL while /WE and /CS are low; the end of /WE sets the capture
// flip-flop of the addressed register; the next word end turns the capture into a one-word write enable (and
// clears the capture), and the register loads REG_DAL_IN in that word: the command register OP (and the wait loop
// of the microprogram leaves for the command: vg93_sequencer), TRK, SEC, DATA. So a written value appears about
// one microword later, and a write that ends while the enable of the previous one is active is lost (the capture
// is set to ~enable).
module vg93_host_bus (
    input  wire sysclk,
    input  wire word_ends,
    input  wire cs_pin, re_pin,           // /CS, /RE active, straight from the pins (DAL output enable)
    input  wire [1:0] addr_pin,
    input  wire cs_q, we_q, re_q,         // sampled: for the chip's logic
    input  wire [1:0] addr_q,
    input  wire [7:0] dal_q,
    input  wire [7:0] status_byte, track_seen, sector_seen, data_seen,
    output reg  [7:0] dal_in = 8'd0,      // REG_DAL_IN
    output reg  [7:0] dal_out,
    output wire dal_oe,
    output wire bus_cmd,                  // access to the status / command register
    output wire bus_data,                 // access to DATA
    output wire bus_data_read,            // read of DATA
    output reg  wr_cmd_en = 1'b0,         // host write enables, one microword long (WR_REG_CMD_EN U106, U112,
    output reg  wr_trk_en = 1'b0,         // U140, U225)
    output reg  wr_sec_en = 1'b0,
    output reg  wr_data_en = 1'b0
);
    localparam [1:0] A_CMD = 2'd0, A_TRK = 2'd1, A_SEC = 2'd2, A_DATA = 2'd3;

    // capture flip-flops (U1007, U938, U953, U1056); they start set: the x -> 0 edge of /WE at power-on arms them
    // (as in the reference simulation), so the first word end after power-on gives one write enable of each register
    reg  cmd_capture = 1'b1, trk_capture = 1'b1, sec_capture = 1'b1, data_capture = 1'b1;

    assign dal_oe = cs_pin && re_pin;
    always @*
        case (addr_pin)
        A_CMD:   dal_out = status_byte;
        A_TRK:   dal_out = track_seen;
        A_SEC:   dal_out = sector_seen;
        default: dal_out = data_seen;
        endcase

    wire wr = we_q && cs_q, rd = re_q && cs_q;
    assign bus_cmd = (wr || rd) && addr_q == A_CMD;
    assign bus_data = (wr || rd) && addr_q == A_DATA;
    assign bus_data_read = rd && addr_q == A_DATA;

    reg wr_prev = 1'b0;
    always @(posedge sysclk) begin
        wr_prev <= wr;
        if (wr) dal_in <= dal_q;
        if (wr_prev && !wr)                           // the end of /WE
            case (addr_q)
            A_CMD:  cmd_capture <= !wr_cmd_en;
            A_TRK:  trk_capture <= !wr_trk_en;
            A_SEC:  sec_capture <= !wr_sec_en;
            A_DATA: data_capture <= !wr_data_en;
            endcase
        if (word_ends) begin                          // a fresh capture becomes the enable and clears
            wr_cmd_en <= !wr_cmd_en && cmd_capture;
            wr_trk_en <= !wr_trk_en && trk_capture;
            wr_sec_en <= !wr_sec_en && sec_capture;
            wr_data_en <= !wr_data_en && data_capture;
            if (!wr_cmd_en && cmd_capture) cmd_capture <= 1'b0;
            if (!wr_trk_en && trk_capture) trk_capture <= 1'b0;
            if (!wr_sec_en && sec_capture) sec_capture <= 1'b0;
            if (!wr_data_en && data_capture) data_capture <= 1'b0;
        end
    end
endmodule
