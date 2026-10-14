-------------------------------------------------------------------------------
-- Testbench: mcu.vhd burst transfers and capability query
-- (karabas-go-firmware docs/burst_protocol.md)
--
-- Plays the RP2040 side: classic 3-byte frames on MCU_SS and bursts on
-- MCU_BURST_CS_N, SPI mode 0 at 16 MHz, mcu CLK at 28 MHz. Checks the
-- CMD_CAPS answer and every ROMLOAD write. Run with run_burst_sim.sh (ISim).
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_mcu_burst is
	generic (
		BURST_SCK_HALF_PS : integer := 31250; -- burst SCK half period (31250 = 16 MHz, 15625 = 32 MHz)
		MAX_MHZ           : integer := 0      -- BURST_MAX_MHZ of the DUT, expected in the CMD_CAPS answer
	);
end tb_mcu_burst;

architecture sim of tb_mcu_burst is

	constant CLK_PERIOD : time := 35.714 ns; -- 28 MHz
	constant SCK_HALF   : time := 31.25 ns;  -- 16 MHz, classic frames
	constant BURST_HALF : time := BURST_SCK_HALF_PS * 1 ps;

	signal clk       : std_logic := '0';
	signal n_reset   : std_logic := '0';
	signal sck       : std_logic := '0';
	signal mosi      : std_logic := '0';
	signal miso      : std_logic;
	signal ss_n      : std_logic := '1';
	signal bcs_n     : std_logic := '1';
	signal ready     : std_logic;

	signal rl_active : std_logic;
	signal rl_addr   : std_logic_vector(31 downto 0);
	signal rl_data   : std_logic_vector(7 downto 0);
	signal rl_wr     : std_logic;

	signal done      : boolean := false;

	-- ROMLOAD write log
	type wr_addr_t is array (0 to 1023) of std_logic_vector(31 downto 0);
	type wr_data_t is array (0 to 1023) of std_logic_vector(7 downto 0);
	signal wr_addr   : wr_addr_t;
	signal wr_data   : wr_data_t;
	signal wr_count  : integer := 0;

	type byte_array is array (natural range <>) of std_logic_vector(7 downto 0);

begin

	clk <= not clk after CLK_PERIOD / 2 when not done;

	DUT: entity work.mcu
	generic map (
		BURST_MAX_MHZ => MAX_MHZ
	)
	port map (
		CLK => clk,
		N_RESET => n_reset,
		MCU_MOSI => mosi,
		MCU_MISO => miso,
		MCU_SCK => sck,
		MCU_SS => ss_n,
		MCU_SPI_FT_SS => '1',
		MCU_SPI_SD2_SS => '1',
		MCU_BURST_CS_N => bcs_n,
		MCU_BURST_READY => ready,
		RTC_A => x"00",
		RTC_DI => x"00",
		RTC_DO => open,
		RTC_CS => '0',
		RTC_WR_N => '1',
		UART_RX_DATA => open,
		UART_RX_IDX => open,
		UART_TX_DATA => x"00",
		UART_TX_WR => '0',
		UART_TX_MODE => '0',
		UART_DLM => x"00",
		UART_DLL => x"00",
		UART_DLM_WR => '0',
		UART_DLL_WR => '0',
		SOFTSW_COMMAND => open,
		ROMLOADER_ACTIVE => rl_active,
		ROMLOAD_ADDR => rl_addr,
		ROMLOAD_DATA => rl_data,
		ROMLOAD_WR => rl_wr,
		FT_MISO => '1',
		MATRIX_CMD => (others => '0'),
		MATRIX_CMD_WR => '0',
		DEBUG_ADDR => (others => '0'),
		DEBUG_DATA => (others => '0'),
		OSD_COMMAND => open,
		BUSY => open
	);

	-- record every ROMLOAD write
	process (clk)
	begin
		if rising_edge(clk) then
			if rl_wr = '1' and rl_active = '1' then
				wr_addr(wr_count) <= rl_addr;
				wr_data(wr_count) <= rl_data;
				wr_count <= wr_count + 1;
			end if;
		end if;
	end process;

	stimulus: process

		-- one spi byte, mode 0: MOSI set while SCK low, sampled on the rising edge
		procedure spi_byte_at(tx : in std_logic_vector(7 downto 0); rx : out std_logic_vector(7 downto 0); half : in time) is
			variable r : std_logic_vector(7 downto 0);
		begin
			for i in 7 downto 0 loop
				mosi <= tx(i);
				wait for half;
				sck <= '1';
				r(i) := miso;
				wait for half;
				sck <= '0';
			end loop;
			rx := r;
		end procedure;

		procedure spi_byte(tx : in std_logic_vector(7 downto 0); rx : out std_logic_vector(7 downto 0)) is
		begin
			spi_byte_at(tx, rx, SCK_HALF);
		end procedure;

		-- classic frame, returns the fpga's frame of the same transfer
		procedure frame(c, a, d : in std_logic_vector(7 downto 0); rc, ra, rd : out std_logic_vector(7 downto 0)) is
		begin
			ss_n <= '0';
			wait for 100 ns;
			spi_byte(c, rc);
			spi_byte(a, ra);
			spi_byte(d, rd);
			wait for 50 ns;
			ss_n <= '1';
			wait for 500 ns;
		end procedure;

		procedure burst(btype : in std_logic_vector(7 downto 0); addr : in unsigned(31 downto 0); data : in byte_array) is
			variable dummy : std_logic_vector(7 downto 0);
			variable a : std_logic_vector(31 downto 0);
		begin
			-- (wait until needs an event: only wait if READY is low now)
			if ready /= '1' then
				wait until ready = '1';
			end if;
			a := std_logic_vector(addr);
			bcs_n <= '0';
			wait for 100 ns;
			spi_byte_at(btype, dummy, BURST_HALF);
			spi_byte_at(a(31 downto 24), dummy, BURST_HALF);
			spi_byte_at(a(23 downto 16), dummy, BURST_HALF);
			spi_byte_at(a(15 downto 8), dummy, BURST_HALF);
			spi_byte_at(a(7 downto 0), dummy, BURST_HALF);
			for i in data'range loop
				spi_byte_at(data(i), dummy, BURST_HALF);
			end loop;
			-- raise CS right after the last byte (the receiver must not lose it)
			bcs_n <= '1';
			wait for 1 us;
		end procedure;

		procedure expect_writes(first : in integer; addr : in unsigned(31 downto 0); data : in byte_array) is
		begin
			for i in data'range loop
				assert wr_addr(first + i) = std_logic_vector(addr + to_unsigned(i, 32))
					report "write " & integer'image(first + i) & ": wrong address" severity error;
				assert wr_data(first + i) = data(i)
					report "write " & integer'image(first + i) & ": wrong data" severity error;
			end loop;
		end procedure;

		variable rc, ra, rd : std_logic_vector(7 downto 0);
		variable caps_seen : boolean := false;
		variable before : integer;
		constant d16 : byte_array(0 to 15) := (x"AA", x"55", x"01", x"02", x"03", x"04", x"05", x"06",
		                                       x"F0", x"0F", x"80", x"7F", x"00", x"FF", x"12", x"34");
		variable d512 : byte_array(0 to 511);

	begin
		n_reset <= '0';
		wait for 1 us;
		n_reset <= '1';
		wait for 2 us;

		-- 1. capability query: answer {F7, 03, 00} in the reply bytes of a following frame
		frame(x"F7", x"00", x"01", rc, ra, rd);
		for i in 1 to 8 loop
			frame(x"FF", x"00", x"00", rc, ra, rd);
			if rc = x"F7" then
				caps_seen := true;
				assert ra = x"03" report "caps: expected 03" severity error;
				assert rd = std_logic_vector(to_unsigned(MAX_MHZ, 8)) report "caps: wrong max_mhz" severity error;
				report "caps answer after " & integer'image(i) & " polls";
				exit;
			end if;
		end loop;
		assert caps_seen report "no CMD_CAPS answer" severity error;

		-- 2. rom loader on, burst of 16 bytes to 0x00001234
		frame(x"08", x"00", x"01", rc, ra, rd); -- CMD_ROMLOADER active
		before := wr_count;
		burst(x"07", x"00001234", d16);
		assert wr_count - before = 16 report "burst 16: expected 16 writes, got " & integer'image(wr_count - before) severity error;
		expect_writes(before, x"00001234", d16);

		-- 3. classic rom frames still work after a burst
		before := wr_count;
		frame(x"06", x"00", x"20", rc, ra, rd); -- rombank addr[15:8]  = 20
		frame(x"06", x"01", x"00", rc, ra, rd); -- rombank addr[23:16] = 00
		frame(x"06", x"02", x"80", rc, ra, rd); -- rombank addr[31:24] = 80 (gs rom area)
		frame(x"07", x"05", x"A5", rc, ra, rd); -- romdata 0x80002005 = A5
		wait for 1 us;
		assert wr_count - before = 1 report "classic: expected 1 write" severity error;
		assert wr_addr(before) = x"80002005" and wr_data(before) = x"A5" report "classic: wrong write" severity error;

		-- 4. unknown burst type: ignored
		before := wr_count;
		burst(x"55", x"00003000", d16);
		assert wr_count = before report "unknown type: unexpected writes" severity error;

		-- 5. full size burst (512 bytes)
		for i in d512'range loop
			d512(i) := std_logic_vector(to_unsigned((i * 7 + 3) mod 256, 8));
		end loop;
		before := wr_count;
		burst(x"07", x"00010000", d512);
		assert wr_count - before = 512 report "burst 512: expected 512 writes, got " & integer'image(wr_count - before) severity error;
		expect_writes(before, x"00010000", d512);

		report "tb_mcu_burst: finished, " & integer'image(wr_count) & " rom writes";
		done <= true;
		wait;
	end process;

end sim;
