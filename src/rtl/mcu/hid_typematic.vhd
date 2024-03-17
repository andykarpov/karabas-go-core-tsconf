-------------------------------------------------------------------------------
-- MCU HID keyboard typematic
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.conv_integer;
use IEEE.numeric_std.all;
use IEEE.std_logic_unsigned.all;

entity hid_typematic is
	port
	(
	 CLK			 : in std_logic; -- 28 mhz
	 RESET 		 : in std_logic;
	 
	 -- incoming usb hid report data
	 KB_STATUS : in std_logic_vector(7 downto 0);
	 KB_DAT0 : in std_logic_vector(7 downto 0);
	 KB_DAT1 : in std_logic_vector(7 downto 0);
	 KB_DAT2 : in std_logic_vector(7 downto 0);
	 KB_DAT3 : in std_logic_vector(7 downto 0);
	 KB_DAT4 : in std_logic_vector(7 downto 0);
	 KB_DAT5 : in std_logic_vector(7 downto 0);

	 -- output filtered usb hid data with typematic delay / repeat
     O_KB_STATUS: out std_logic_vector(7 downto 0);
     O_KB_DAT0 : out std_logic_vector(7 downto 0);
     O_KB_DAT1 : out std_logic_vector(7 downto 0);
     O_KB_DAT2 : out std_logic_vector(7 downto 0);
     O_KB_DAT3 : out std_logic_vector(7 downto 0);
     O_KB_DAT4 : out std_logic_vector(7 downto 0);
     O_KB_DAT5 : out std_logic_vector(7 downto 0)
	 
	);
end hid_typematic;

architecture rtl of hid_typematic is

    signal data : std_logic_vector(55 downto 0);
    signal prev_data : std_logic_vector(55 downto 0);
    signal odata : std_logic_vector(55 downto 0);
    
    signal cnt : std_logic_vector(24 downto 0) := (others => '0');
    signal delay_500_ms : std_logic_vector(24 downto 0) := "0110101011001111110000000"; -- 14000000;
    signal delay_100_ms : std_logic_vector(24 downto 0) := "0001010101011100110000000"; --  2800000;
    signal delay_50_ms : std_logic_vector(24 downto 0)  := "0000101010101110011000000"; --  1400000;

    type qmachine IS(idle, delay, release, repeat, repeat_delay, repeat_release);
	signal qstate : qmachine := idle;

begin 

    data <= kb_status & kb_dat5 & kb_dat4 & kb_dat3 & kb_dat2 & kb_dat1 & kb_dat0;

    process (clk, reset)
    begin
        if reset = '1' then
            odata <= (others => '0');    
        elsif rising_edge(clk) then
            prev_data <= data;

            case qstate is
                when idle => 
                    odata <= data;
                    if (prev_data = data and data(47 downto 0) /= "000000000000000000000000000000000000000000000000") then 
                        cnt <= delay_500_ms;                        
                        qstate <= delay;
                    end if;

                when delay => 
                    if (cnt > 0) then 
                        cnt <= cnt - 1;
                        if (prev_data /= data) then
                            qstate <= idle;
                        end if;
                    else 
                        cnt <= delay_100_ms;
                        qstate <= release;
                    end if;

                when release => 
                    odata <= (others => '0');
                    if (cnt > 0) then 
                        cnt <= cnt - 1;
                        if (prev_data /= data) then
                            qstate <= idle;
                        end if;
                    else
                        qstate <= repeat;
                    end if;

                when repeat => 
                    odata <= data;
                    cnt <= delay_50_ms;
                    qstate <= repeat_delay;

                when repeat_delay => 
                    if (cnt > 0) then 
                        cnt <= cnt - 1;
                        if (prev_data /= data) then
                            qstate <= idle;
                        end if;
                    else 
                        cnt <= delay_50_ms;
                        qstate <= repeat_release;
                    end if;

                when repeat_release => 
                    odata <= (others => '0');
                    if (cnt > 0) then 
                        cnt <= cnt - 1;
                        if (prev_data /= data) then
                            qstate <= idle;
                        end if;
                    else
                        qstate <= repeat;
                    end if;
                    
            end case;
            
    
        end if;

    end process;

    O_KB_STATUS <= odata(55 downto 48);
    O_KB_DAT5 <= odata(47 downto 40);
    O_KB_DAT4 <= odata(39 downto 32);
    O_KB_DAT3 <= odata(31 downto 24);
    O_KB_DAT2 <= odata(23 downto 16);
    O_KB_DAT1 <= odata(15 downto 8);
    O_KB_DAT0 <= odata(7 downto 0);

end rtl;
