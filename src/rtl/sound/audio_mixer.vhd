-------------------------------------------------------------------------------
-- Audio Mixer
-------------------------------------------------------------------------------

library IEEE; 
use IEEE.std_logic_1164.all; 
use IEEE.std_logic_unsigned.all;
use IEEE.numeric_std.all; 
 
entity audio_mixer is
	port ( 
        clk : in std_logic;
        
        mute: in std_logic; -- 1 = mute, 0 - normal
        mode: in std_logic_vector(1 downto 0); -- 00 = ABC, 01 = ACB, 10 = mono

        speaker: in std_logic;
        tape_in: in std_logic;

        ssg0_a: in std_logic_vector(7 downto 0);
        ssg0_b: in std_logic_vector(7 downto 0);
        ssg0_c: in std_logic_vector(7 downto 0);
        ssg1_a: in std_logic_vector(7 downto 0);
        ssg1_b: in std_logic_vector(7 downto 0);
        ssg1_c: in std_logic_vector(7 downto 0);
        
        covox_a: in std_logic_vector(7 downto 0);
        covox_b: in std_logic_vector(7 downto 0);
        covox_c: in std_logic_vector(7 downto 0);
        covox_d: in std_logic_vector(7 downto 0);
        covox_fb: in std_logic_vector(7 downto 0);

        saa_l: in std_logic_vector(7 downto 0);
        saa_r: in std_logic_vector(7 downto 0);
		  
		  gs_l : in std_logic_vector(14 downto 0);
		  gs_r : in std_logic_vector(14 downto 0);

        audio_l : out std_logic_vector(15 downto 0);
        audio_r : out std_logic_vector(15 downto 0)

	);
end audio_mixer;
 
architecture rtl of audio_mixer is
    signal audio_mono		: std_logic_vector(15 downto 0);
begin

process (clk)
begin
    if rising_edge(clk) then
        audio_mono <= 	
				        ("000000" & speaker & "000000000") +
--				        ("0000000" & tape_in & "00000000") +				
				        ("000000"  & ssg0_a &        "00") + 
				        ("000000"  & ssg0_b &        "00") + 
				        ("000000"  & ssg0_c &        "00") + 
				        ("000000"  & ssg1_a &        "00") + 
				        ("000000"  & ssg1_b &        "00") + 
				        ("000000"  & ssg1_c &        "00") + 
				        ("000000"  & covox_a &       "00") + 
				        ("000000"  & covox_b &       "00") + 
				        ("000000"  & covox_c &       "00") + 
				        ("000000"  & covox_d &       "00") + 
				        ("000000"  & covox_fb &      "00") + 
				        ("000000"  & saa_l &         "00") + 				
				        ("000000"  & saa_r &         "00") + 
						  ("000000"  & gs_l(14 downto 5)   ) + 
						  ("000000"  & gs_r(14 downto 5)   );
						  
		  -- mute
		  if mute = '1' then 
			audio_l <= (others => '0');
			audio_r <= (others => '0');

		  -- mono
		  elsif (mode = "10") then 
			audio_l <= audio_mono;
			audio_r <= audio_mono;

		  -- ACB
		  elsif (mode = "01") then 
		   audio_l <= ("00000" & speaker & "0000000000") + -- ACB: L = A + C/2
--				        ("0000000" & tape_in & "00000000") +	
				        ("00000"  & ssg0_a &        "000") + 
				        ("000000"  & ssg0_c &        "00") + 
				        ("00000"  & ssg1_a &        "000") + 
				        ("000000"  & ssg1_c &        "00") + 
				        ("00000"  & covox_a &       "000") + 
				        ("00000"  & covox_b &       "000") + 
				        ("00000"  & covox_fb &      "000") + 
				        ("00000"  & saa_l  &        "000") + 
						  ("00000"  & gs_l(14 downto 4)    );
			audio_r <= ("00000" & speaker & "0000000000") + -- ACB: R = B + C/2
--				        ("0000000" & tape_in & "00000000") +	
				        ("00000"  & ssg0_b &        "000") + 
				        ("000000"  & ssg0_c &        "00") + 
				        ("00000"  & ssg1_b &        "000") + 
				        ("000000"  & ssg1_c &        "00") + 
				        ("00000"  & covox_c &       "000") + 
				        ("00000"  & covox_d &       "000") + 
				        ("00000"  & covox_fb &      "000") + 
				        ("00000"  & saa_r &         "000") +
						  ("00000"  & gs_r(14 downto 4)    );
		  -- ABC
		  else 
		   audio_l <= ("00000" & speaker & "0000000000") +  -- ABC: L = A + B/2
--				        ("0000000" & tape_in &    "00000000") +	
				        ("00000"  & ssg0_a &        "000") + 
				        ("000000"  & ssg0_b &        "00") + 
				        ("00000"  & ssg1_a &        "000") + 
				        ("000000"  & ssg1_b &        "00") + 
				        ("00000"  & covox_a &       "000") + 
				        ("00000"  & covox_b &       "000") + 
				        ("00000"  & covox_fb &      "000") + 
				        ("00000"  & saa_l  &        "000") +
						  ("00000"  & gs_l(14 downto 4)    );
			audio_r <= ("00000" & speaker & "0000000000") + -- ABC: R = C + B/2
--				        ("0000000" & tape_in & "00000000") +	
				        ("00000"  & ssg0_c &        "000") + 
				        ("000000"  & ssg0_b &        "00") + 
				        ("00000"  & ssg1_c &        "000") + 
				        ("000000"  & ssg1_b &        "00") + 
				        ("00000"  & covox_c &       "000") + 
				        ("00000"  & covox_d &       "000") + 
				        ("00000"  & covox_fb &      "000") + 
				        ("00000"  & saa_r &         "000") +
						  ("00000"  & gs_r(14 downto 4)    );
		  end if;
    end if;
end process;

end rtl;	
