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
	keycode	: out std_logic_vector(7 downto 0)
);
end usb_ps2_lut;

architecture rtl of usb_ps2_lut is

begin
	process (kb_status, kb_data)
	begin
		keycode <= x"FF";
		
		if kb_data /= "00000000" then 
				case kb_data is
					-- Letters
					when X"04" =>	KEYCODE <= x"1c"; -- A
					when X"05" =>	KEYCODE <= x"32"; -- B								
					when X"06" =>	KEYCODE <= x"21"; -- C
					when X"07" =>	KEYCODE <= x"23"; -- D
					when X"08" =>	KEYCODE <= x"24"; -- E
					when X"09" =>	KEYCODE <= x"2b"; -- F
					when X"0a" =>	KEYCODE <= x"34"; -- G
					when X"0b" =>	KEYCODE <= x"33"; -- H
					when X"0c" =>	KEYCODE <= x"43"; -- I
					when X"0d" =>	KEYCODE <= x"3b"; -- J
					when X"0e" =>	KEYCODE <= x"42"; -- K
					when X"0f" =>	KEYCODE <= x"4b"; -- L
					when X"10" =>	KEYCODE <= x"3a"; -- M
					when X"11" =>	KEYCODE <= x"31"; -- N
					when X"12" =>	KEYCODE <= x"44"; -- O
					when X"13" =>	KEYCODE <= x"4d"; -- P
					when X"14" =>	KEYCODE <= x"15"; -- Q
					when X"15" =>	KEYCODE <= x"2d"; -- R
					when X"16" =>	KEYCODE <= x"1b"; -- S
					when X"17" =>	KEYCODE <= x"2c"; -- T
					when X"18" =>	KEYCODE <= x"3c"; -- U
					when X"19" =>	KEYCODE <= x"2a"; -- V
					when X"1a" =>	KEYCODE <= x"1d"; -- W
					when X"1b" =>	KEYCODE <= x"22"; -- X
					when X"1c" =>	KEYCODE <= x"35"; -- Y
					when X"1d" =>	KEYCODE <= x"1a"; -- Z
					
					-- Digits
					when X"1e" =>	KEYCODE <= x"16"; -- 1
					when X"1f" =>	KEYCODE <= x"1e"; -- 2
					when X"20" =>	KEYCODE <= x"26"; -- 3
					when X"21" =>	KEYCODE <= x"25"; -- 4
					when X"22" =>	KEYCODE <= x"2e"; -- 5
					when X"23" =>	KEYCODE <= x"36"; -- 6
					when X"24" =>	KEYCODE <= x"3d"; -- 7
					when X"25" =>	KEYCODE <= x"3e"; -- 8
					when X"26" =>	KEYCODE <= x"46"; -- 9
					when X"27" =>	KEYCODE <= x"45"; -- 0

					-- Numpad digits
					when X"59" =>	KEYCODE <= x"16"; -- 1
					when X"5A" =>	KEYCODE <= x"1e"; -- 2
					when X"5B" =>	KEYCODE <= x"26"; -- 3
					when X"5C" =>	KEYCODE <= x"25"; -- 4
					when X"5D" =>	KEYCODE <= x"2e"; -- 5
					when X"5E" =>	KEYCODE <= x"36"; -- 6
					when X"5F" =>	KEYCODE <= x"3d"; -- 7
					when X"60" =>	KEYCODE <= x"3e"; -- 8
					when X"61" =>	KEYCODE <= x"46"; -- 9
					when X"62" =>	KEYCODE <= x"45"; -- 0
					
					when x"4c" => KEYCODE <= x"71"; -- Del
					when x"49" => KEYCODE <= x"70"; -- Ins
					when x"50" => KEYCODE <= x"6b"; -- Cursor
					when x"51" => KEYCODE <= x"72";
					when x"52" => KEYCODE <= x"75";
					when x"4f" => KEYCODE <= x"74";
					when x"29" => KEYCODE <= x"76"; -- Esc
					when x"2a" => KEYCODE <= x"66"; -- Backspace
					when x"28" => KEYCODE <= x"5a"; -- Enter
					when x"58" => KEYCODE <= x"5a"; -- Keypad Enter
					when x"2c" => KEYCODE <= x"29"; -- Space
					when x"34" => KEYCODE <= x"52"; -- ' "
					when x"36" => KEYCODE <= x"41"; -- , <
					when x"37" => KEYCODE <= x"49"; -- . >
					when x"33" => KEYCODE <= x"4c"; -- ; :
					when x"2f" => KEYCODE <= x"54"; -- [ {
					when x"30" => KEYCODE <= x"5b"; -- ] }
					when x"38" => KEYCODE <= x"4a"; -- / ? 
					when x"31" => KEYCODE <= x"5d"; -- \ |
					when x"2e" => KEYCODE <= x"55"; -- = +
					when x"2d" => KEYCODE <= x"4e"; -- - _
					when x"35" => KEYCODE <= x"0e"; -- ` ~
					when x"55" => KEYCODE <= x"FF"; -- keypad * : todo 
					when x"56" => KEYCODE <= x"FF"; -- keypad - : todo  
					when x"57" => KEYCODE <= x"FF"; -- keypad + : todo 
					when x"2b" => KEYCODE <= x"0d"; -- Tab
					when x"39" => KEYCODE <= x"58"; -- Capslock
					when x"4b" => KEYCODE <= x"7d"; -- PgUp
					when x"4e" => KEYCODE <= x"7a"; -- PgDn
					when x"4a" => KEYCODE <= x"6c"; -- Home
					when x"4d" => KEYCODE <= x"69"; -- End
		
					-- Fx keys
					when X"3a" => KEYCODE <= x"05";	-- F1
					when X"3b" => KEYCODE <= x"06";	-- F2
					when X"3c" => KEYCODE <= x"04";	-- F3
					when X"3d" => KEYCODE <= x"0c";	-- F4
					when X"3e" => KEYCODE <= x"03";	-- F5
					when X"3f" => KEYCODE <= x"0b";	-- F6
					when X"40" => KEYCODE <= x"83";	-- F7
					when X"41" => KEYCODE <= x"0a";	-- F8
					when X"42" => KEYCODE <= x"01";	-- F9
					when X"43" => KEYCODE <= x"09";	-- F10
					when X"44" => KEYCODE <= x"78";	-- F11
					when X"45" => KEYCODE <= x"07";	-- F12
		 
					-- Soft-only keys
					when X"46" =>	KEYCODE <= x"7c";	-- PrtScr
					when X"47" =>	KEYCODE <= x"7e";	-- Scroll Lock
					when X"48" =>	KEYCODE <= x"77";	-- Pause
					when X"65" =>	KEYCODE <= x"2f";	-- WinMenu
					when others => null;
				end case;
		else
		
				if    KB_STATUS(1) = '1' then KEYCODE <= X"12"; -- L shift
				elsif KB_STATUS(5) = '1' then KEYCODE <= X"59"; -- R shift
				elsif KB_STATUS(0) = '1' then KEYCODE <= X"14"; -- L ctrl
				elsif KB_STATUS(4) = '1' then KEYCODE <= X"14"; -- R ctrl
				elsif KB_STATUS(2) = '1' then KEYCODE <= X"11"; -- L Alt
				elsif KB_STATUS(6) = '1' then KEYCODE <= X"11"; -- R Alt
				elsif KB_STATUS(7) = '1' then KEYCODE <= x"27"; -- Win
				end if;
		
		end if;
		
	end process;
end rtl;