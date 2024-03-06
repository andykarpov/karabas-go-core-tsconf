-------------------------------------------------------------------------------
-- USB to PS/2 lut
-------------------------------------------------------------------------------

library IEEE; 
use IEEE.std_logic_1164.all; 
use IEEE.std_logic_unsigned.all;
use IEEE.numeric_std.all; 

entity usb_ps2_lut is
port (
	kb_status : in std_logic_vector(7 downto 0);
	kb_data : in std_logic_vector(7 downto 0);
	keycode	: buffer std_logic_vector(8 downto 0) -- keycode(8) = E0
);
end usb_ps2_lut;

architecture rtl of usb_ps2_lut is

begin
	process (kb_status, kb_data)
	begin
		keycode <= "011111111"; -- 0xFF
		
		if kb_data /= "00000000" then 
				case kb_data is
					-- Letters
					when X"04" =>	KEYCODE(7 downto 0) <= x"1c"; -- A
					when X"05" =>	KEYCODE(7 downto 0) <= x"32"; -- B								
					when X"06" =>	KEYCODE(7 downto 0) <= x"21"; -- C
					when X"07" =>	KEYCODE(7 downto 0) <= x"23"; -- D
					when X"08" =>	KEYCODE(7 downto 0) <= x"24"; -- E
					when X"09" =>	KEYCODE(7 downto 0) <= x"2b"; -- F
					when X"0a" =>	KEYCODE(7 downto 0) <= x"34"; -- G
					when X"0b" =>	KEYCODE(7 downto 0) <= x"33"; -- H
					when X"0c" =>	KEYCODE(7 downto 0) <= x"43"; -- I
					when X"0d" =>	KEYCODE(7 downto 0) <= x"3b"; -- J
					when X"0e" =>	KEYCODE(7 downto 0) <= x"42"; -- K
					when X"0f" =>	KEYCODE(7 downto 0) <= x"4b"; -- L
					when X"10" =>	KEYCODE(7 downto 0) <= x"3a"; -- M
					when X"11" =>	KEYCODE(7 downto 0) <= x"31"; -- N
					when X"12" =>	KEYCODE(7 downto 0) <= x"44"; -- O
					when X"13" =>	KEYCODE(7 downto 0) <= x"4d"; -- P
					when X"14" =>	KEYCODE(7 downto 0) <= x"15"; -- Q
					when X"15" =>	KEYCODE(7 downto 0) <= x"2d"; -- R
					when X"16" =>	KEYCODE(7 downto 0) <= x"1b"; -- S
					when X"17" =>	KEYCODE(7 downto 0) <= x"2c"; -- T
					when X"18" =>	KEYCODE(7 downto 0) <= x"3c"; -- U
					when X"19" =>	KEYCODE(7 downto 0) <= x"2a"; -- V
					when X"1a" =>	KEYCODE(7 downto 0) <= x"1d"; -- W
					when X"1b" =>	KEYCODE(7 downto 0) <= x"22"; -- X
					when X"1c" =>	KEYCODE(7 downto 0) <= x"35"; -- Y
					when X"1d" =>	KEYCODE(7 downto 0) <= x"1a"; -- Z
					
					-- Digits
					when X"1e" =>	KEYCODE(7 downto 0) <= x"16"; -- 1
					when X"1f" =>	KEYCODE(7 downto 0) <= x"1e"; -- 2
					when X"20" =>	KEYCODE(7 downto 0) <= x"26"; -- 3
					when X"21" =>	KEYCODE(7 downto 0) <= x"25"; -- 4
					when X"22" =>	KEYCODE(7 downto 0) <= x"2e"; -- 5
					when X"23" =>	KEYCODE(7 downto 0) <= x"36"; -- 6
					when X"24" =>	KEYCODE(7 downto 0) <= x"3d"; -- 7
					when X"25" =>	KEYCODE(7 downto 0) <= x"3e"; -- 8
					when X"26" =>	KEYCODE(7 downto 0) <= x"46"; -- 9
					when X"27" =>	KEYCODE(7 downto 0) <= x"45"; -- 0

					-- Numpad digits
					when X"59" =>	KEYCODE(7 downto 0) <= x"16"; -- 1
					when X"5A" =>	KEYCODE(7 downto 0) <= x"1e"; -- 2
					when X"5B" =>	KEYCODE(7 downto 0) <= x"26"; -- 3
					when X"5C" =>	KEYCODE(7 downto 0) <= x"25"; -- 4
					when X"5D" =>	KEYCODE(7 downto 0) <= x"2e"; -- 5
					when X"5E" =>	KEYCODE(7 downto 0) <= x"36"; -- 6
					when X"5F" =>	KEYCODE(7 downto 0) <= x"3d"; -- 7
					when X"60" =>	KEYCODE(7 downto 0) <= x"3e"; -- 8
					when X"61" =>	KEYCODE(7 downto 0) <= x"46"; -- 9
					when X"62" =>	KEYCODE(7 downto 0) <= x"45"; -- 0
					
					when x"4c" => KEYCODE(7 downto 0) <= x"71"; keycode(8) <= '1'; -- Del
					when x"49" => KEYCODE(7 downto 0) <= x"70"; keycode(8) <= '1';-- Ins
					when x"50" => KEYCODE(7 downto 0) <= x"6b"; keycode(8) <= '1'; -- Cursor
					when x"51" => KEYCODE(7 downto 0) <= x"72"; keycode(8) <= '1';
					when x"52" => KEYCODE(7 downto 0) <= x"75"; keycode(8) <= '1';
					when x"4f" => KEYCODE(7 downto 0) <= x"74"; keycode(8) <= '1';
					when x"29" => KEYCODE(7 downto 0) <= x"76"; -- Esc
					when x"2a" => KEYCODE(7 downto 0) <= x"66"; -- Backspace
					when x"28" => KEYCODE(7 downto 0) <= x"5a"; -- Enter
					when x"58" => KEYCODE(7 downto 0) <= x"5a"; keycode(8) <= '1'; -- Keypad Enter
					when x"2c" => KEYCODE(7 downto 0) <= x"29"; -- Space
					when x"34" => KEYCODE(7 downto 0) <= x"52"; -- ' "
					when x"36" => KEYCODE(7 downto 0) <= x"41"; -- , <
					when x"37" => KEYCODE(7 downto 0) <= x"49"; -- . >
					when x"33" => KEYCODE(7 downto 0) <= x"4c"; -- ; :
					when x"2f" => KEYCODE(7 downto 0) <= x"54"; -- [ {
					when x"30" => KEYCODE(7 downto 0) <= x"5b"; -- ] }
					when x"38" => KEYCODE(7 downto 0) <= x"4a"; -- / ? 
					when x"31" => KEYCODE(7 downto 0) <= x"5d"; -- \ |
					when x"2e" => KEYCODE(7 downto 0) <= x"55"; -- = +
					when x"2d" => KEYCODE(7 downto 0) <= x"4e"; -- - _
					when x"35" => KEYCODE(7 downto 0) <= x"0e"; -- ` ~
					when x"55" => KEYCODE(7 downto 0) <= x"FF"; -- keypad * : todo 
					when x"56" => KEYCODE(7 downto 0) <= x"FF"; -- keypad - : todo  
					when x"57" => KEYCODE(7 downto 0) <= x"FF"; -- keypad + : todo 
					when x"2b" => KEYCODE(7 downto 0) <= x"0d"; -- Tab
					when x"39" => KEYCODE(7 downto 0) <= x"58"; -- Capslock
					when x"4b" => KEYCODE(7 downto 0) <= x"7d"; keycode(8) <= '1'; -- PgUp
					when x"4e" => KEYCODE(7 downto 0) <= x"7a"; keycode(8) <= '1'; -- PgDn
					when x"4a" => KEYCODE(7 downto 0) <= x"6c"; keycode(8) <= '1'; -- Home
					when x"4d" => KEYCODE(7 downto 0) <= x"69"; keycode(8) <= '1'; -- End
		
					-- Fx keys
					when X"3a" => KEYCODE(7 downto 0) <= x"05";	-- F1
					when X"3b" => KEYCODE(7 downto 0) <= x"06";	-- F2
					when X"3c" => KEYCODE(7 downto 0) <= x"04";	-- F3
					when X"3d" => KEYCODE(7 downto 0) <= x"0c";	-- F4
					when X"3e" => KEYCODE(7 downto 0) <= x"03";	-- F5
					when X"3f" => KEYCODE(7 downto 0) <= x"0b";	-- F6
					when X"40" => KEYCODE(7 downto 0) <= x"83";	-- F7
					when X"41" => KEYCODE(7 downto 0) <= x"0a";	-- F8
					when X"42" => KEYCODE(7 downto 0) <= x"01";	-- F9
					when X"43" => KEYCODE(7 downto 0) <= x"09";	-- F10
					when X"44" => KEYCODE(7 downto 0) <= x"78";	-- F11
					when X"45" => KEYCODE(7 downto 0) <= x"07";	-- F12
		 
					-- Soft-only keys
					when X"46" =>	KEYCODE(7 downto 0) <= x"7c";	-- PrtScr
					when X"47" =>	KEYCODE(7 downto 0) <= x"7e";	-- Scroll Lock
					when X"48" =>	KEYCODE(7 downto 0) <= x"77";	-- Pause
					when X"65" =>	KEYCODE(7 downto 0) <= x"2f"; keycode(8) <= '1'; -- WinMenu  
					when others => null;
				end case;
		else	
				if    KB_STATUS(1) = '1' then KEYCODE(7 downto 0) <= X"12"; -- L shift
				elsif KB_STATUS(5) = '1' then KEYCODE(7 downto 0) <= X"59"; -- R shift
				elsif KB_STATUS(0) = '1' then KEYCODE(7 downto 0) <= X"14"; -- L ctrl
				elsif KB_STATUS(4) = '1' then KEYCODE(7 downto 0) <= X"14"; keycode(8) <= '1'; -- R ctrl
				elsif KB_STATUS(2) = '1' then KEYCODE(7 downto 0) <= X"11"; -- L Alt
				elsif KB_STATUS(6) = '1' then KEYCODE(7 downto 0) <= X"11"; keycode(8) <= '1'; -- R Alt
				elsif KB_STATUS(7) = '1' then KEYCODE(7 downto 0) <= x"27"; keycode(8) <= '1'; -- R Win 
				end if;
		
		end if;
		
	end process;
end rtl;