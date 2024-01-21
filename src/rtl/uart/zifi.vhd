--------------------------------------------------------------------------------
-- ZiFi module (API v1)
-- https://github.com/HackerVBI/ZiFi/blob/master/_esp/upd1/README!!__eRS232.txt
--
-- @author Andy Karpov <andy.karpov@gmail.com>
-- Ukraine, 2023
--------------------------------------------------------------------------------
library IEEE; 
use IEEE.std_logic_1164.all; 
use IEEE.std_logic_unsigned.all;
use IEEE.numeric_std.all; 

entity zifi is
port(
    CLK         : in std_logic;
    RESET       : in std_logic;
	 DS80        : in std_logic;

    A           : in std_logic_vector(15 downto 0);
    DI          : in std_logic_vector(7 downto 0);
    DO          : out std_logic_vector(7 downto 0);
    IORQ_N      : in std_logic;
    RD_N        : in std_logic;
    WR_N        : in std_logic;

    ZIFI_OE_N   : out std_logic;
	 
	 ENABLED     : out std_logic;

    UART_RX     : in std_logic;
    UART_TX     : out std_logic;
    UART_CTS    : out std_logic        
);
end zifi;

architecture rtl of zifi is

component uart 
port ( 
    clk_bus     : in std_logic;
	 ds80        : in std_logic;
    txdata      : in std_logic_vector(7 downto 0);
    txbegin     : in std_logic;
    txbusy      : out std_logic;
    rxdata      : out std_logic_vector(7 downto 0);
    rxrecv      : out std_logic;
    data_read   : in std_logic;
    rx          : in std_logic;
    tx          : out std_logic;
    rts         : out std_logic);
end component;

constant zifi_command_port  : std_logic_vector(15 downto 0) := x"C7EF"; -- 51183
constant zifi_error_port    : std_logic_vector(15 downto 0) := x"C7EF"; -- 51183
constant zifi_data_port     : std_logic_vector(15 downto 0) := x"BFEF"; -- 49135
constant zifi_in_fifo_port  : std_logic_vector(15 downto 0) := x"C0EF"; -- 49391
constant zifi_out_fifo_port : std_logic_vector(15 downto 0) := x"C1EF"; -- 49647
constant zifi_fifo_size     : std_logic_vector(7 downto 0) := x"FF";

signal command_reg          : std_logic_vector(7 downto 0);
signal err_reg              : std_logic_vector(7 downto 0);
signal di_reg               : std_logic_vector(7 downto 0);
signal do_reg               : std_logic_vector(7 downto 0);
signal api_enabled          : std_logic := '1';

signal fifo_tx_di           : std_logic_vector(7 downto 0);
signal fifo_tx_do           : std_logic_vector(7 downto 0);
signal fifo_tx_rd_req       : std_logic := '0';
signal fifo_tx_wr_req       : std_logic := '0';
signal fifo_tx_clr_req      : std_logic := '0';
signal fifo_tx_used         : std_logic_vector(7 downto 0) := (others => '0');
signal fifo_tx_full 			 : std_logic;
signal fifo_tx_empty 		 : std_logic;

signal fifo_rx_di          : std_logic_vector(7 downto 0);
signal fifo_rx_do          : std_logic_vector(7 downto 0);
signal fifo_rx_rd_req      : std_logic := '0';
signal fifo_rx_wr_req      : std_logic := '0';
signal fifo_rx_clr_req     : std_logic := '0';
signal fifo_rx_used        : std_logic_vector(10 downto 0) := (others => '0');
signal fifo_rx_full 			: std_logic;
signal fifo_rx_empty       : std_logic;

signal fifo_rx_free        : std_logic_vector(7 downto 0) := (others => '1');
signal fifo_tx_free         : std_logic_vector(7 downto 0) := (others => '1');

signal tx_begin_req         : std_logic := '0';
signal txbusy               : std_logic := '0';
signal txdone 				    : std_logic := '0';
signal data_received        : std_logic;
signal data_read            : std_logic;

signal wr_allow : std_logic := '1';
signal rd_allow : std_logic := '1';
signal new_command : std_logic := '0';

type txmachine IS (idle, pull_tx_fifo, end_pull_tx_fifo, req_uart_tx, end_req_uart_tx);
type rxmachine IS (idle, push_rx_fifo, end_push_rx_fifo, ack_uart_read);

signal txstate : txmachine := idle; 
signal rxstate : rxmachine := idle;

begin

FIFO_IN: entity work.fifo
port map(
    clk => CLK,
    din  => fifo_tx_di,
    rd_en => fifo_tx_rd_req,
    wr_en => fifo_tx_wr_req,
    srst  => fifo_tx_clr_req,
    dout     => fifo_tx_do,
    data_count => fifo_tx_used,
	 full => fifo_tx_full,
	 empty => fifo_tx_empty
);

FIFO_OUT: entity work.fifo2
port map(
    clk => CLK,
    din  => fifo_rx_di,
    rd_en => fifo_rx_rd_req,
    wr_en => fifo_rx_wr_req,
    srst  => fifo_rx_clr_req,
    dout     => fifo_rx_do,
    data_count => fifo_rx_used,
	 full => fifo_rx_full,
	 empty => fifo_rx_empty
);

UART_receiver: entity work.uart_rx
port map(
	i_Clk => CLK,
	i_RX_Serial => UART_RX,
	o_RX_DV => fifo_rx_wr_req,
	o_RX_Byte => fifo_rx_di
);

UART_transmitter: entity work.uart_tx
port map(
	i_Clk => CLK,
	i_TX_DV => tx_begin_req,
	i_TX_Byte => fifo_tx_do,
	o_TX_Active => txbusy,
	o_TX_Serial => UART_TX,
	o_TX_Done => txdone
);

fifo_tx_di <= di_reg;
do_reg <= fifo_rx_do;

process (RESET, CLK)
begin
	 if RESET = '1' then 
			fifo_tx_rd_req <= '0';
			tx_begin_req <= '0';
			txstate <= idle;
			rxstate <= idle;
			
    elsif rising_edge(CLK) then

			tx_begin_req <= '0';

		  -- fifo tx -> uart tx 
		  case txstate is
	
			when idle => 
				-- if tx fifo is not empty and transmitter is not busy
				if (fifo_tx_empty = '0' and txbusy = '0') then 
					txstate <= pull_tx_fifo;
				end if;

			-- request to read byte from fifo
			when pull_tx_fifo =>  
				fifo_tx_rd_req <= '1';
				txstate <= end_pull_tx_fifo;

			-- end request to read byte from fifo
			when end_pull_tx_fifo => 
				fifo_tx_rd_req <= '0';
				txstate <= req_uart_tx;

			-- begin uart tx request
			when req_uart_tx => 
				tx_begin_req <= '1';
				txstate <= end_req_uart_tx;

		   -- end uart tx request
			when end_req_uart_tx => 
				tx_begin_req <= '0';
				if (txdone = '1') then -- wait txdone from transmitter
				  txstate <= idle;
				end if;
				
			when others => null;
		  end case;

    end if;
end process;

process (CLK, RESET) 
begin
    if (RESET = '1') then
        command_reg <= (others => '0');
        di_reg <= (others => '0');
		  new_command <= '0';
		  wr_allow <= '1';
		  rd_allow <= '1';
		  fifo_tx_wr_req <= '0';
		  api_enabled <= '1';
		  
    elsif (rising_edge(CLK)) then
	 
		fifo_tx_clr_req <= '0';
		fifo_rx_clr_req <= '0';
	 
        -- fifo_tx write request
        if IORQ_N = '0' and WR_N = '0' then 
			 if A = zifi_command_port then 
				if (wr_allow = '1' and new_command = '0') then 
					command_reg <= DI;
					wr_allow <= '0';
					new_command <= '1'; 
				end if;
			 end if;
          if A(7 downto 0) = zifi_data_port(7 downto 0) and A(15 downto 8) <= zifi_data_port(15 downto 8) then 
				if (fifo_tx_wr_req = '0' and wr_allow = '1') then
					wr_allow <= '0';
					di_reg <= DI; fifo_tx_wr_req <= '1';
				end if;
			 end if; 
        end if;
		  if (WR_N = '1') then 
			wr_allow <= '1';
		  end if;
        if (fifo_tx_wr_req = '1') then 
            fifo_tx_wr_req <= '0';
        end if;

        -- fifo_rx read request
        if IORQ_N = '0' and RD_N = '0' and A(7 downto 0) = zifi_data_port(7 downto 0) and A(15 downto 8) <= zifi_data_port(15 downto 8) and fifo_rx_empty = '0' then
				if (fifo_rx_rd_req = '0' and rd_allow = '1') then
					fifo_rx_rd_req <= '1';
					rd_allow <= '0';
				end if;
        end if;
        if (fifo_rx_rd_req = '1') then
            fifo_rx_rd_req <= '0';
        end if;
		  if (RD_N = '1') then 
				rd_allow <= not fifo_rx_empty;
		  end if;
		  
		  --  
		  if new_command = '1' then
			  case (command_reg) is
					when "00000001" => fifo_rx_clr_req  <= '1'; err_reg <= (others => '0'); new_command <= '0';  -- clear rx fifo
					when "00000010" => fifo_tx_clr_req <= '1'; err_reg <= (others => '0'); new_command <= '0'; -- clear tx fifo
					when "00000011" => fifo_tx_clr_req  <= '1'; err_reg <= (others => '0'); fifo_rx_clr_req <= '1'; new_command <= '0'; -- clear both in/out fifo
					when "11110000" => api_enabled      <= '0'; err_reg <= (others => '0'); new_command <= '0'; -- api disabled
					when "11110001" => api_enabled      <= '1'; err_reg <= (others => '0'); new_command <= '0'; -- api transparent
					when "11111111" => -- get API version
											 if (api_enabled = '1') then 
												  err_reg <= "00000001"; 
											 else 
												  err_reg <= "11111111"; 
											 end if;
											 new_command <= '0';
					when others => err_reg <= "11111111"; new_command <= '0';
			  end case;
		  end if;
    end if;
end process;

DO <= "10111111"  when IORQ_N = '0' and RD_N = '0' and A = zifi_in_fifo_port and fifo_rx_used > 191  else 
	fifo_rx_used(7 downto 0)  when IORQ_N = '0' and RD_N = '0' and A = zifi_in_fifo_port  else 
   fifo_tx_free when IORQ_N = '0' and RD_N = '0' and A = zifi_out_fifo_port else 
   err_reg       when IORQ_N = '0' and RD_N = '0' and A = zifi_error_port    else 
   do_reg        when IORQ_N = '0' and RD_N = '0' and A(7 downto 0) = zifi_data_port(7 downto 0) and A(15 downto 8) <= zifi_data_port(15 downto 8) else 
   "11111111";

fifo_tx_free <= std_logic_vector(unsigned(zifi_fifo_size) - unsigned(fifo_tx_used));
        
ZIFI_OE_N <= '0' when IORQ_N = '0' and RD_N = '0' and (A = zifi_in_fifo_port or A = zifi_out_fifo_port or A = zifi_error_port or (A(7 downto 0) = zifi_data_port(7 downto 0) and A(15 downto 8) <= zifi_data_port(15 downto 8))  ) else '1';

ENABLED <= api_enabled;

UART_CTS <= '1' when fifo_rx_used > 1792 else '0'; -- active 0

end rtl;
