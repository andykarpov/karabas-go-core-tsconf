-------------------------------------------------------------------------------
-- MCU -> FPGA burst receiver
--
-- Protocol: karabas-go-firmware docs/burst_protocol.md
--
-- While CS_N is low the MCU sends (SPI mode 0, MSB first):
--   TYPE, ADDR[31:24], ADDR[23:16], ADDR[15:8], ADDR[7:0], D0, D1, ... Dn-1
-- For every data byte Dk this entity outputs ADDR+k / Dk with a one-CLK WR_O
-- pulse. A new burst starts with a new header after CS_N went high.
--
-- The shift register is clocked by SCK (like spi_slave), every completed byte
-- is handed over to the CLK domain with a toggle synchronizer. The byte
-- holding register is stable for the next 8 SCK periods, so CLK must see the
-- toggle within that time: 8 / f_SCK > 5 / f_CLK (e.g. CLK 28 MHz -> SCK up
-- to ~40 MHz; report less in the CMD_CAPS max_mhz answer to have margin).
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity burst_rx is
	port (
		CLK      : in  std_logic;                      -- system clock
		SCK      : in  std_logic;                      -- spi clock (shared with the classic link)
		MOSI     : in  std_logic;
		CS_N     : in  std_logic;                      -- BURST_CS_N

		TYPE_O   : out std_logic_vector(7 downto 0);  -- burst type of the current burst (target)
		ADDR_O   : out std_logic_vector(31 downto 0); -- address of DATA_O
		DATA_O   : out std_logic_vector(7 downto 0);
		WR_O     : out std_logic := '0';               -- one CLK pulse per data byte
		ACTIVE_O : out std_logic                       -- 1 while CS_N is low (CLK domain)
	);
end burst_rx;

architecture rtl of burst_rx is

	-- SCK domain
	signal bitcnt    : unsigned(2 downto 0) := (others => '0');
	signal shreg     : std_logic_vector(6 downto 0) := (others => '0');
	signal byte_hold : std_logic_vector(7 downto 0) := (others => '0');
	signal byte_tgl  : std_logic := '0';

	-- CLK domain
	signal tgl_sync  : std_logic_vector(2 downto 0) := (others => '0');
	signal cs_sync   : std_logic_vector(1 downto 0) := (others => '1');
	signal idx       : unsigned(2 downto 0) := (others => '0'); -- 0 = type, 1..4 = address, 5 = data
	signal btype     : std_logic_vector(7 downto 0) := (others => '0');
	signal addr      : unsigned(31 downto 0) := (others => '0');

begin

	-- bit counter, restarts at every CS_N assertion
	process (SCK, CS_N)
	begin
		if CS_N = '1' then
			bitcnt <= (others => '0');
		elsif rising_edge(SCK) then
			bitcnt <= bitcnt + 1;
		end if;
	end process;

	-- shift register and byte handover (not reset: the last byte must survive CS_N going high)
	process (SCK)
	begin
		if rising_edge(SCK) then
			if CS_N = '0' then
				shreg <= shreg(5 downto 0) & MOSI;
				if bitcnt = "111" then
					byte_hold <= shreg & MOSI;
					byte_tgl <= not byte_tgl;
				end if;
			end if;
		end if;
	end process;

	process (CLK)
	begin
		if rising_edge(CLK) then
			tgl_sync <= tgl_sync(1 downto 0) & byte_tgl;
			cs_sync <= cs_sync(0) & CS_N;
			WR_O <= '0';

			if tgl_sync(2) /= tgl_sync(1) then
				-- a new byte (processed before the idle reset below, so the last byte of a
				-- burst is not lost when CS_N rises right after it)
				case to_integer(idx) is
					when 0 => btype <= byte_hold;
					when 1 => addr(31 downto 24) <= unsigned(byte_hold);
					when 2 => addr(23 downto 16) <= unsigned(byte_hold);
					when 3 => addr(15 downto 8) <= unsigned(byte_hold);
					when 4 => addr(7 downto 0) <= unsigned(byte_hold);
					when others =>
						DATA_O <= byte_hold;
						ADDR_O <= std_logic_vector(addr);
						WR_O <= '1';
						addr <= addr + 1;
				end case;
				if idx /= 5 then
					idx <= idx + 1;
				end if;
			elsif cs_sync(1) = '1' then
				-- idle: the next byte is the type of a new burst
				idx <= (others => '0');
			end if;
		end if;
	end process;

	TYPE_O <= btype;
	ACTIVE_O <= not cs_sync(1);

end rtl;
