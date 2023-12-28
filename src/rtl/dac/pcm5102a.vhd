-------------------------------------------------------------------[11.11.2023]
-- PCM5102A I2S Audio Controller
-- Andy Karpov 2023
-------------------------------------------------------------------------------

-- (PCM5102A) I2S Mode MSB First
-- STATE     01  02  03  04  05  06  07  08  09  0A  0B  ..  0F  10  11  12  13  14  15  16  17  18  19  1A  1B  ..  1F  00
--      ___  __  __  __  __  __  __  __  __  __  __  __  ..  __  __  __  __  __  __  __  __  __  __  __  __  __  ..  __  __  ____
-- DATA    \/LS\/MS\/  \/  \/  \/  \/  \/  \/  \/  \/  \/  \/  \/  \/LS\/MS\/  \/  \/  \/  \/  \/  \/  \/  \/  \/  \/  \/  \/   
--      ___/\__/\__/\__/\__/\__/\__/\__/\__/\__/\__/\__/\../\__/\__/\__/\__/\__/\__/\__/\__/\__/\__/\__/\__/\__/\../\__/\__/\____
--          -0- -F- -E- -D- -C- -B- -A- -9- -8- -7- -6-  .. -2- -1- -0- -F- -E- -D- -C- -B- -A- -9- -8- -7- -6-  .. -2- -1- 
--        _   _   _   _   _   _   _   _   _   _   _   _  ..   _   _   _   _   _   _   _   _   _   _   _   _   _  ..   _   _   _ 
-- BCK   | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | |
--      _| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_
--             |
--      ___    |                                                     ____________________________________________..
-- RLCK    |   |            LEFT                                   |                RIGHT                          |
--         |___|_________________________________________..________|                                               |_____________
--             |SAMPLE OUT

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.std_logic_unsigned.all;

entity pcm5102a is
    Port (
    RESET: in std_logic;
    CLK_BUS: in std_logic;
    CS: in std_logic;
    DATA_L: in std_logic_vector (15 downto 0);
    DATA_R: in std_logic_vector (15 downto 0);
    BCK: out std_logic;
    LRCK: out std_logic;
    DATA: out std_logic 
);
end pcm5102a;
 
architecture pcm5102a_arch of pcm5102a is

signal shift_reg : std_logic_vector(31 downto 0) := (others => '0');
signal cnt : std_logic_vector(5 downto 0) := (others => '0');
signal cnt_clk : std_logic_vector(1 downto 0) := (others => '0');

begin

-- clk counter 
process (RESET, CS, CLK_BUS, cnt_clk)
begin 
    if (RESET = '1' or CS = '0') then 
        cnt_clk <= (others => '0');
    elsif (falling_edge(CLK_BUS)) then 
        cnt_clk <= cnt_clk + 1;
    end if;
end process;

-- counter
process (RESET, CS, CLK_BUS, cnt, cnt_clk)
begin 
    if (RESET = '1' or CS = '0') then 
        cnt <= (others => '0');
    elsif (CLK_BUS'event and CLK_BUS = '0' and cnt_clk = "00") then
        if (cnt < 31) then 
            cnt <= cnt + 1;
        else
            cnt <= (others => '0');
        end if;
    end if;
end process;

-- LRCK
process (RESET, CS, CLK_BUS, cnt_clk, cnt)
begin 
    if (RESET = '1' or CS = '0') then 
        LRCK <= '0';
    elsif (CLK_BUS'event and CLK_BUS = '0' and cnt_clk = "00") then
        if cnt = 31 then 
            LRCK <= '0'; -- LEFT
        elsif cnt = 15 then 
            LRCK <= '1'; -- RIGHT
        end if;
    end if;
end process;

-- shift register
process (RESET, CLK_BUS, cnt_clk, CS, shift_reg, DATA_L, DATA_R)
begin
    if (RESET = '1' or CS = '0') then
        shift_reg <= (others => '0');
    elsif (CLK_BUS'event and CLK_BUS = '0' and cnt_clk = "00") then
        if cnt = 0 then
            shift_reg(31 downto 0) <= DATA_L & DATA_R;
        else
            shift_reg <= shift_reg(30 downto 0) & '0';
        end if;
    end if;
end process;

DATA <= shift_reg(31);
BCK <= '0' when cnt_clk(1) = '1' and CS = '1' else '1';

end pcm5102a_arch;