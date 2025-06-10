library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity freq_counter is
generic (
	fs_ref 				  : integer := 28000000 -- 28 MHz ref fs
);
port (
  i_clk_ref            : in  std_logic;
  i_clk_test           : in  std_logic;
  i_reset              : in  std_logic;
  o_freq         		  : out std_logic_vector(7 downto 0) -- in MHz
);
end freq_counter;

architecture rtl of freq_counter is

signal cnt : std_logic_vector(15 downto 0) := (others => '0');
signal measure : std_logic_vector(15 downto 0) := (others => '0');
signal freq : std_logic_vector(15 downto 0) := (others => '0');

constant time_interval : integer := fs_ref / 1000; -- measure time interval
constant time_div : integer := 16; -- measure test clock div factor
signal test : std_logic_vector(3 downto 0) := "0000"; -- test signal rising counter
signal test_r : std_logic_vector(1 downto 0); -- register to transfer test(3) to ref clock domain
signal prev_test_r : std_logic;
signal prev_freq : std_logic_vector(15 downto 0);

begin

-- convert i_clk_test to test counter (div4)
process (i_clk_test)
begin
	if rising_edge(i_clk_test) then
		test <= test + 1;
	end if;
end process;

-- cross domain test clock
process (i_clk_ref)
begin
	if rising_edge(i_clk_ref) then
		test_r(0) <= test(3);
		test_r(1) <= test_r(0);
	end if;
end process;

-- measuring interval counter
process (i_clk_ref)
begin
	if rising_edge(i_clk_ref) then 
		if (cnt < time_interval) then 
			cnt <= cnt + 1;
		else
			cnt <= (others => '0');
		end if;
	end if;
end process;

-- measuring freq counter by rising_edge
process (i_clk_ref)
begin
	if rising_edge(i_clk_ref) then
		prev_test_r <= test_r(1);
		if (cnt = 0) then 
			freq <= measure;
			measure <= (others => '0');
		else
			if (prev_test_r = '0' and test_r(1) = '1') then
				measure <= measure + 1;
			end if;
		end if;
	end if;
end process;

-- align measured freq to known frequencies
process (i_clk_ref)
begin
	if rising_edge(i_clk_ref) then
		
		if (prev_freq /= freq) then
			if (freq > 75000/time_div) then
				o_freq <= x"50"; -- 80 MHz
			elsif (freq > 70000/time_div) then 
				o_freq <= x"48"; -- 72 MHz
			elsif (freq > 60000/time_div) then
				o_freq <= x"40"; -- 64 MHz
			elsif (freq > 53000/time_div) then 
				o_freq <= x"38"; -- 56 MHz
			elsif (freq >= 43000/time_div) then 
				o_freq <= x"30"; -- 48 MHz
			elsif (freq >= 35000/time_div) then 
				o_freq <= x"28"; -- 40 MHz
			elsif (freq >= 30000/time_div) then 
				o_freq <= x"20"; -- 32 MHz
			elsif (freq >= 26000/time_div) then
				o_freq <= x"1C"; -- 28 MHz
			elsif (freq >= 22000/time_div) then
				o_freq <= x"18"; -- 24 MHz
			else 
				o_freq <= x"1C"; -- 28 MHz (default fallback)
			end if;
		end if;
		prev_freq <= freq;
	end if;
end process;

end rtl;