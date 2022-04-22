library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

--The IEEE.std_logic_unsigned contains definitions that allow 
--std_logic_vector types to be used with the + operator to instantiate a 
--counter.
use IEEE.std_logic_unsigned.all;

entity GPIO_demo is
    Port ( 
			ck_rst		: in STD_LOGIC;
			ja          : inout STD_LOGIC_VECTOR ( 3 TO 4);
			SW 			: in  STD_LOGIC_VECTOR (3 downto 0);
			BTN 			: in  STD_LOGIC_VECTOR (3 downto 0);
			CLK 			: in  STD_LOGIC;
			LED 			: out  STD_LOGIC_VECTOR (3 downto 0);
			UART_TXD 	: out  STD_LOGIC
			  );
end GPIO_demo;

architecture Behavioral of GPIO_demo is

component pmod_hygrometer IS
GENERIC(
    sys_clk_freq            : INTEGER;        --input clock speed from user logic in Hz
    humidity_resolution     : INTEGER RANGE 0 TO 14;  --RH resolution in bits (must be 14, 11, or 8)
    temperature_resolution  : INTEGER RANGE 0 TO 14); --temperature resolution in bits (must be 14 or 11)
  PORT(
    clk               : IN    STD_LOGIC;                                            --system clock
    reset_n           : IN    STD_LOGIC;                                            --asynchronous active-low reset
    scl               : INOUT STD_LOGIC;                                            --I2C serial clock
    sda               : INOUT STD_LOGIC;                                            --I2C serial data
    i2c_ack_err       : OUT   STD_LOGIC;                                            --I2C slave acknowledge error flag
    relative_humidity : OUT   STD_LOGIC_VECTOR(humidity_resolution-1 DOWNTO 0);     --relative humidity data obtained
    temperature       : OUT   STD_LOGIC_VECTOR(temperature_resolution-1 DOWNTO 0)); --temperature data obtained
END component;
  
component UART_TX_CTRL
Port(
	SEND : in std_logic;
	DATA : in std_logic_vector(7 downto 0);
	CLK : in std_logic;          
	READY : out std_logic;
	UART_TX : out std_logic
	);
end component;

component debouncer
Generic(
        DEBNC_CLOCKS : integer;
        PORT_WIDTH : integer);
Port(
		SIGNAL_I : in std_logic_vector(3 downto 0);
		CLK_I : in std_logic;          
		SIGNAL_O : out std_logic_vector(3 downto 0)
		);
end component;

--The type definition for the UART state machine type. Here is a description of what
--occurs during each state:
-- RST_REG     -- Do Nothing. This state is entered after configuration or a user reset.
--                The state is set to LD_INIT_STR.
-- LD_INIT_STR -- The Welcome String is loaded into the sendStr variable and the strIndex
--                variable is set to zero. The welcome string length is stored in the StrEnd
--                variable. The state is set to SEND_CHAR.
-- SEND_CHAR   -- uartSend is set high for a single clock cycle, signaling the character
--                data at sendStr(strIndex) to be registered by the UART_TX_CTRL at the next
--                cycle. Also, strIndex is incremented (behaves as if it were post 
--                incremented after reading the sendStr data). The state is set to RDY_LOW.
-- RDY_LOW     -- Do nothing. Wait for the READY signal from the UART_TX_CTRL to go low, 
--                indicating a send operation has begun. State is set to WAIT_RDY.
-- WAIT_RDY    -- Do nothing. Wait for the READY signal from the UART_TX_CTRL to go high, 
--                indicating a send operation has finished. If READY is high and strEnd = 
--                StrIndex then state is set to WAIT_BTN, else if READY is high and strEnd /=
--                StrIndex then state is set to SEND_CHAR.
-- WAIT_BTN    -- Do nothing. Wait for a button press on BTNU, BTNL, BTND, or BTNR. If a 
--                button press is detected, set the state to LD_BTN_STR.
-- LD_BTN_STR  -- The Button String is loaded into the sendStr variable and the strIndex
--                variable is set to zero. The button string length is stored in the StrEnd
--                variable. The state is set to SEND_CHAR.
type UART_STATE_TYPE is (RST_REG, LD_INIT_STR, SEND_CHAR, RDY_LOW, WAIT_RDY, WAIT_BTN, LD_BTN_STR);




--The CHAR_ARRAY type is a variable length array of 8 bit std_logic_vectors. 
--Each std_logic_vector contains an ASCII value and represents a character in
--a string. The character at index 0 is meant to represent the first
--character of the string, the character at index 1 is meant to represent the
--second character of the string, and so on.
type CHAR_ARRAY is array (integer range<>) of std_logic_vector(7 downto 0);

constant HUM_RES : integer := 14;
constant TEM_RES : integer := 14;
constant TMR_CNTR_MAX : std_logic_vector(26 downto 0) := "101111101011110000100000000"; --100,000,000 = clk cycles per second
constant TMR_VAL_MAX : std_logic_vector(3 downto 0) := "1001"; --9

constant RESET_CNTR_MAX : std_logic_vector(17 downto 0) := "110000110101000000";-- 100,000,000 * 0.002 = 200,000 = clk cycles per 2 ms

constant MAX_STR_LEN : integer := 64;

--Welcome string definition. Note that the values stored at each index
--are the ASCII values of the indicated character.
constant WELCOME_STR : CHAR_ARRAY(0 to 23) := 
(x"0d", x"0a", x"54", x"45", x"4d", x"5f", x"48", x"55", x"4d", x"20", x"73", x"65", x"6e", x"73", x"69", x"6e", x"67", x"20", x"6e", x"6f", x"77", x"3a", x"0a", x"0d");
-- TEM_HUM sensing now:
-- string length containing CRLF: 24

--constant BTN_STR: CHAR_ARRAY(0 to 9) := 
--(X"20", X"44",X"20", X"44",X"20", X"44", X"54", X"54", x"0a", x"0d");
signal tmrCntr : std_logic_vector(26 downto 0) := (others => '0');

--This counter keeps track of which number is currently being displayed
--on the 7-segment.
signal tmrVal : std_logic_vector(3 downto 0) := (others => '0');

--Contains the current string being sent over uart.
signal sendStr : CHAR_ARRAY(0 to (MAX_STR_LEN - 1)) := (others => x"20");

--Contains the length of the current string being sent over uart.
signal strEnd : natural;

--Contains the index of the next character to be sent over uart
--within the sendStr variable.
signal strIndex : natural;

--Used to determine when a button press has occured
signal btnReg : std_logic_vector (3 downto 0) := "0000";
signal btnDetect : std_logic;

--UART_TX_CTRL control signals
signal uartRdy : std_logic;
signal uartSend : std_logic := '0';
signal uartData : std_logic_vector (7 downto 0):= "00000000";
signal uartTX : std_logic;

--Current uart state signal
signal uartState : UART_STATE_TYPE := RST_REG;

--Debounced btn signals used to prevent single button presses
--from being interpreted as multiple button presses.
signal btnDeBnc : std_logic_vector(3 downto 0);

signal clk_cntr_reg : std_logic_vector (4 downto 0) := (others=>'0'); 

--signal pwm_val_reg : std_logic := '0';

--this counter counts the amount of time paused in the UART reset state
signal reset_cntr : std_logic_vector (17 downto 0) := (others=>'0');

SIGNAL humidity_data    : STD_LOGIC_VECTOR((HUM_RES-1) DOWNTO 0); --humidity data buffer
SIGNAL temperature_data : STD_LOGIC_VECTOR((TEM_RES-1) DOWNTO 0); --temperature data buffer
signal i2c_ackerr : std_logic;
SIGNAL serialclk : std_logic ;
signal serialdata: std_logic ;
signal printout_data : CHAR_ARRAY (0 TO (HUM_RES+TEM_RES+3)) := (OTHERS=>X"00");

-- type CHAR_ARRAY is array (integer range<>) of std_logic_vector(7 downto 0);
function slv_to_charary ( src : std_logic_vector) return CHAR_ARRAY is
constant slv : std_logic_vector := src;
variable strdata : CHAR_ARRAY (1 to slv'length) := (others => x"20");
variable stridx : natural := 1; 
begin
    for i in slv'range loop
--        strdata(stridx) := std_logic'image(slv((i)))(2);
        if slv(i) = '1' then
            strdata(stridx) := x"31";
        else 
            strdata(stridx) := x"30";
        end if;
        stridx := stridx+1;
    end loop;
return strdata;
end function;

function add_CRLF( src : CHAR_ARRAY ) return CHAR_ARRAY is
constant srcdata : CHAR_ARRAY := src;
constant srclen : integer := srcdata'length;
variable dstdata : CHAR_ARRAY (1 to srclen+2) := (others => x"00");
begin 
    dstdata(1 to srclen) := srcdata;
    dstdata((srclen+1) to (srclen+2)) := (x"0d", x"0a"); -- "0d" is \r, "0a" is \n
    return dstdata;
end function;

function printout_raw (temsrc : std_logic_vector; humsrc : std_logic_vector)
return CHAR_ARRAY is
    constant temdata : std_logic_vector := temsrc;
    constant humdata : std_logic_vector := humsrc;
    constant outlen : integer := HUM_RES+TEM_RES+4;
    variable charout : CHAR_ARRAY(1 to outlen);
    begin
        charout(1 to (TEM_RES+2)) := add_CRLF(slv_to_charary(temdata)); -- TEM
        charout((TEM_RES+3) to outlen) := add_CRLF(slv_to_charary(humdata)); -- HUM
    return charout;
end function;
--function readhum (src: std_logic_vector) return CHAR_ARRAY is
--    constant srcdata : std_logic_vector := src;
--    variable humdata : real := 0.0;
--    variable idx : integer := 0;
--    variable stri: integer := 0;
--    -- 4 digit precision RH display, with . and %
--    variable humstr : string (1 to 5) := "";
--    variable humout : CHAR_ARRAY (1 to 6) := (others=> x"00");
--    begin
--        while idx < HUM_RES loop
--            humdata := humdata + srcdata(HUM_RES-1-idx)*2**(-idx-1);
--            idx := idx+1;
--        end loop;
--        humstr := real'image(humdata);
--        idx := 1;
--        while idx < 4 loop
--            if idx = 3 THEN
--                humout(3) := (x"2e"); -- '.'
--                stri := stri + 1;
----            humout(stri+idx) := (x "character'val(humstr(idx))");
--            humout(stri+idx) := humstr(idx);
--            idx := idx + 1;
--            end if;
--        end loop;
--        humout(6) := (x"25"); -- '%'
--    return humout;
--end function;

begin
----------------------------------------------------------
------                LED Control                  -------
----------------------------------------------------------


	LED <= SW;
			 			 

----------------------------------------------------------
------              Button Control                 -------
----------------------------------------------------------
--Buttons are debounced and their rising edges are detected
--to trigger UART messages


--Debounces btn signals 
Inst_btn_debounce: debouncer 
    generic map(
        DEBNC_CLOCKS => (2**16),
        PORT_WIDTH => 4)
    port map(
		SIGNAL_I => BTN,
		CLK_I => CLK,
		SIGNAL_O => btnDeBnc
	);

--Registers the debounced button signals, for edge detection.
btn_reg_process : process (CLK)
begin
	if (rising_edge(CLK)) then
		btnReg <= btnDeBnc(3 downto 0);
	end if;
end process;

--btnDetect goes high for a single clock cycle when a btn press is
--detected. This triggers a UART message to begin being sent.
btnDetect <= '1' when ((btnReg(0)='0' and btnDeBnc(0)='1') or
								(btnReg(1)='0' and btnDeBnc(1)='1') or
								(btnReg(2)='0' and btnDeBnc(2)='1') or
								(btnReg(3)='0' and btnDeBnc(3)='1')  ) else
				  '0';
				  



----------------------------------------------------------
------              UART Control                   -------
----------------------------------------------------------
--Messages are sent on reset and when a button is pressed.

--This counter holds the UART state machine in reset for ~2 milliseconds. This
--will complete transmission of any byte that may have been initiated during 
--FPGA configuration due to the UART_TX line being pulled low, preventing a 
--frame shift error from occuring during the first message.
process(CLK)
begin
  if (rising_edge(CLK)) then
    if ((reset_cntr = RESET_CNTR_MAX) or (uartState /= RST_REG)) then
      reset_cntr <= (others=>'0');
    else
      reset_cntr <= reset_cntr + 1;
    end if;
  end if;
end process;

--Next Uart state logic (states described above)


next_uartState_process : process (CLK)
begin
	if (rising_edge(CLK)) then
        if(SW(0) = '0') then 
            uartState <= RST_REG;        
        end if;			
			case uartState is 
			when RST_REG =>
        if (reset_cntr = RESET_CNTR_MAX) then
          uartState <= LD_INIT_STR;
        end if;
			when LD_INIT_STR =>
				uartState <= SEND_CHAR;
			when SEND_CHAR =>
				uartState <= RDY_LOW;
			when RDY_LOW =>
				uartState <= WAIT_RDY;
			when WAIT_RDY =>
				if (uartRdy = '1') then
					if (strEnd = strIndex) then
						uartState <= WAIT_BTN;
					else
						uartState <= SEND_CHAR;
					end if;
				end if;
			when WAIT_BTN =>
				if (btnDetect = '1') then
					uartState <= LD_BTN_STR;
				end if;
			when LD_BTN_STR =>
				uartState <= SEND_CHAR;
			when others=> --should never be reached
				uartState <= RST_REG;
			end case;
		
	end if;
end process;

--Loads the sendStr and strEnd signals when a LD state is
--is reached.
string_load_process : process (CLK)
begin
	if (rising_edge(CLK)) then
		if (uartState = LD_INIT_STR) then
			sendStr(0 TO (WELCOME_STR'length-1)) <= WELCOME_STR;
			strEnd <= WELCOME_STR'length;
		elsif (uartState = LD_BTN_STR) then
            printout_data <= printout_raw(temperature_data, humidity_data);
			sendStr(0 to (printout_data'length-1)) <= printout_data;
			strEnd <= printout_data'length;
		end if;
	end if;
end process;

--Conrols the strIndex signal so that it contains the index
--of the next character that needs to be sent over uart
char_count_process : process (CLK)
begin
	if (rising_edge(CLK)) then
		if (uartState = LD_INIT_STR or uartState = LD_BTN_STR) then
			strIndex <= 0;
		elsif (uartState = SEND_CHAR) then
			strIndex <= strIndex + 1;
		end if;
	end if;
end process;

--Controls the UART_TX_CTRL signals
char_load_process : process (CLK)
begin
	if (rising_edge(CLK)) then
		if (uartState = SEND_CHAR) then
			uartSend <= '1';
			uartData <= sendStr(strIndex);
		else
			uartSend <= '0';
		end if;
	end if;
end process;

--Component used to send a byte of data over a UART line.
Inst_UART_TX_CTRL: UART_TX_CTRL port map(
		SEND => uartSend,
		DATA => uartData,
		CLK => CLK,
		READY => uartRdy,
		UART_TX => uartTX 
	);

UART_TXD <= uartTX;

------------------------------------
Inst_Hygrometer: pmod_hygrometer
GENERIC map(
    sys_clk_freq            => 100_000_000,        --input clock speed from user logic in Hz
    humidity_resolution     => HUM_RES ,  --RH resolution in bits (must be 14, 11, or 8)
    temperature_resolution  => TEM_RES ) --temperature resolution in bits (must be 14 or 11)
PORT map(
    clk               => CLK,                                            --system clock
    reset_n           => SW(0),                                          --asynchronous active-low reset
    scl               => ja(3) ,                                            --I2C serial clock
    sda               => ja(4) ,                                            --I2C serial data
    i2c_ack_err       => i2c_ackerr,                                            --I2C slave acknowledge error flag
    relative_humidity => humidity_data((HUM_RES-1)  DOWNTO 0),     --relative humidity data obtained
    temperature       => temperature_data((TEM_RES-1) downto 0)); --temperature data obtained

end Behavioral;
