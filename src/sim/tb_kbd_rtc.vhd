-------------------------------------------------------------------------------
-- Testbench: the PS/2 keyboard buffer of tsconf through the RTC registers
--
-- kg_mcu (the configuration of the tops) and hid_parser as wired in the tops.
-- The RP2040 side sends CMD_PS2_SCANCODE frames (SPI mode 0, 16 MHz); the CPU
-- side writes RTC register 0C (bit 7 = 0: F0..FF read the keyboard buffer)
-- and reads F0 as the gluclock port does (rtc_rd high for an IO cycle, data
-- taken at its end). Also a USB report frame against the key matrix (KB_DO).
-- Run with run_kbd_sim.sh (ISim). Ends with "tb_kbd_rtc: N errors".
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_kbd_rtc is
end tb_kbd_rtc;

architecture sim of tb_kbd_rtc is

	constant CLK_PERIOD : time := 35.714 ns; -- clk_bus
	constant SCK_HALF   : time := 31.25 ns;

	signal clk       : std_logic := '0';
	signal n_reset   : std_logic := '0';
	signal reset     : std_logic;
	signal sck       : std_logic := '0';
	signal mosi      : std_logic := '0';
	signal miso      : std_logic;
	signal ss_n      : std_logic := '1';

	signal rtc_a     : std_logic_vector(7 downto 0) := x"00";
	signal rtc_di    : std_logic_vector(7 downto 0) := x"00";
	signal rtc_do    : std_logic_vector(7 downto 0);
	signal rtc_do_m  : std_logic_vector(7 downto 0);
	signal rtc_wr    : std_logic := '0';
	signal rtc_rd    : std_logic := '0';
	signal rtc_wr_n  : std_logic;

	signal kb_status, kb0, kb1, kb2, kb3, kb4, kb5 : std_logic_vector(7 downto 0);
	signal scancode  : std_logic_vector(7 downto 0);
	signal scancode_upd : std_logic;
	signal joy_l, joy_r : std_logic_vector(12 downto 0);
	signal kb_a      : std_logic_vector(15 downto 8) := x"FF";
	signal kb_do     : std_logic_vector(5 downto 0);
	signal joy_do    : std_logic_vector(7 downto 0);

	signal done      : boolean := false;
	signal errors    : integer := 0;

begin

	clk <= not clk after CLK_PERIOD / 2 when not done;
	reset <= not n_reset;
	rtc_wr_n <= not rtc_wr;

	DUT: entity work.kg_mcu
	generic map (
		BURST_MAX_MHZ => 0, CS_FILTER => 3, ENABLE_RTC => 1, RTC_SKIP_0D => 0, RTC_SEND_LIMIT => 240,
		ENABLE_UART => 1, ENABLE_MATRIX => 0, ENABLE_DEBUG => 0, ENABLE_IMG => 0, ENABLE_FILE => 0,
		ENABLE_FT => 1, ENABLE_SD2 => 0
	)
	port map (
		CLK => clk, N_RESET => n_reset,
		MCU_MOSI => mosi, MCU_MISO => miso, MCU_SCK => sck, MCU_SS => ss_n,
		MCU_SPI_FT_SS => '1', MCU_SPI_SD2_SS => '1', MCU_BURST_CS_N => '1',
		KB_STATUS => kb_status, KB_DAT0 => kb0, KB_DAT1 => kb1, KB_DAT2 => kb2,
		KB_DAT3 => kb3, KB_DAT4 => kb4, KB_DAT5 => kb5,
		KB_SCANCODE => scancode, KB_SCANCODE_UPD => scancode_upd,
		JOY_L => joy_l, JOY_R => joy_r,
		RTC_A => rtc_a, RTC_DI => rtc_di, RTC_DO => rtc_do, RTC_CS => '1', RTC_WR_N => rtc_wr_n,
		UART_TX_DATA => x"00", UART_TX_WR => '0', UART_TX_MODE => '0',
		UART_DLM => x"00", UART_DLL => x"00", UART_DLM_WR => '0', UART_DLL_WR => '0',
		FT_MISO => '1', SD2_MISO => '1',
		MATRIX_CMD => x"000000", MATRIX_CMD_WR => '0',
		DEBUG_ADDR => x"0000", DEBUG_DATA => x"0000",
		IMG_Q_WR => '0', IMG_Q_DI => x"000000"
	);

	HID: entity work.hid_parser
	port map (
		CLK => clk, RESET => reset,
		KB_STATUS => kb_status, KB_DAT0 => kb0, KB_DAT1 => kb1, KB_DAT2 => kb2,
		KB_DAT3 => kb3, KB_DAT4 => kb4, KB_DAT5 => kb5,
		KB_SCANCODE => scancode, KB_SCANCODE_UPD => scancode_upd,
		JOY_TYPE_L => "000", JOY_TYPE_R => "000", JOY_L => joy_l, JOY_R => joy_r,
		KB_TYPE => '1', A => kb_a, JOY_DO => joy_do, KB_DO => kb_do,
		RTC_A => rtc_a, RTC_WR => rtc_wr, RTC_RD => rtc_rd, RTC_DI => rtc_di,
		RTC_DO_IN => rtc_do, RTC_DO_OUT => rtc_do_m
	);

	stimulus: process

		procedure fail(msg : in string) is
		begin
			errors <= errors + 1;
			report "ERROR: " & msg severity warning;
			wait for 0 ns;
		end procedure;

		procedure spi_byte(tx : in std_logic_vector(7 downto 0)) is
		begin
			for i in 7 downto 0 loop
				mosi <= tx(i);
				wait for SCK_HALF;
				sck <= '1';
				wait for SCK_HALF;
				sck <= '0';
			end loop;
		end procedure;

		procedure frame(c, a, d : in std_logic_vector(7 downto 0)) is
		begin
			ss_n <= '0';
			wait for 100 ns;
			spi_byte(c); spi_byte(a); spi_byte(d);
			wait for 50 ns;
			ss_n <= '1';
			wait for 500 ns;
		end procedure;

		-- an IO cycle of the gluclock port: address set before, rtc_rd / rtc_wr for 8 clocks,
		-- inputs changed at the falling edge
		procedure rtc_write(a, d : in std_logic_vector(7 downto 0)) is
		begin
			wait until falling_edge(clk);
			rtc_a <= a; rtc_di <= d;
			for i in 1 to 4 loop wait until falling_edge(clk); end loop;
			rtc_wr <= '1';
			for i in 1 to 8 loop wait until falling_edge(clk); end loop;
			rtc_wr <= '0';
			for i in 1 to 4 loop wait until falling_edge(clk); end loop;
		end procedure;

		procedure rtc_read(a : in std_logic_vector(7 downto 0); expect : in std_logic_vector(7 downto 0)) is
		begin
			wait until falling_edge(clk);
			rtc_a <= a;
			for i in 1 to 4 loop wait until falling_edge(clk); end loop;
			rtc_rd <= '1';
			for i in 1 to 8 loop wait until falling_edge(clk); end loop;
			if rtc_do_m /= expect then
				fail("read " & integer'image(to_integer(unsigned(a))) & ": " &
					integer'image(to_integer(unsigned(rtc_do_m))) & ", expected " &
					integer'image(to_integer(unsigned(expect))));
			end if;
			rtc_rd <= '0';
			for i in 1 to 4 loop wait until falling_edge(clk); end loop;
		end procedure;

	begin
		n_reset <= '0';
		wait for 1 us;
		n_reset <= '1';
		wait for 2 us;

		-- the keyboard buffer on (register 0C, bit 7 = 0)
		rtc_write(x"0C", x"00");

		-- 'A' pressed and released (set 2: 1C, F0 1C)
		frame(x"0B", x"00", x"1C");
		frame(x"0B", x"00", x"F0");
		frame(x"0B", x"00", x"1C");
		wait for 2 us;
		rtc_read(x"F0", x"1C");
		rtc_read(x"F0", x"F0");
		rtc_read(x"F0", x"1C");
		rtc_read(x"F0", x"00"); -- empty

		-- interleaved with reads
		frame(x"0B", x"00", x"5A");
		rtc_read(x"F0", x"5A");
		rtc_read(x"F0", x"00");

		-- register 0C bit 0: reset the buffer
		frame(x"0B", x"00", x"29");
		rtc_write(x"0C", x"01");
		rtc_read(x"F0", x"00");

		-- USB report: 'A' (HID 04) on the matrix, row A9 (FDFE: A, S, D, F, G)
		frame(x"01", x"01", x"04");
		wait for 2 us;
		kb_a <= x"FD";
		wait for 1 us;
		if kb_do(0) /= '0' then fail("matrix: A not pressed"); end if;
		frame(x"01", x"01", x"00");
		wait for 2 us;
		if kb_do(0) /= '1' then fail("matrix: A not released"); end if;

		wait for 1 us;
		report "tb_kbd_rtc: " & integer'image(errors) & " errors";
		done <= true;
		wait;
	end process;

end sim;
